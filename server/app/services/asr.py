"""ASR abstraction.

Production uses faster-whisper with word_timestamps=True. When the heavy
dependency / model is unavailable (dev laptop), the stub backend returns a
deterministic word-level transcript so the whole client flow can be tested.
"""
from __future__ import annotations

import os
import tempfile
import threading
from dataclasses import dataclass
from urllib.parse import urlparse

import httpx

from ..core.config import REPO_ROOT, get_settings


@dataclass
class AsrWord:
    w: str
    s: float
    e: float
    p: float | None = None


@dataclass
class AsrSegment:
    id: int
    start: float
    end: float
    text: str
    words: list[AsrWord]


@dataclass
class AsrResult:
    language: str
    duration: float
    segments: list[AsrSegment]


_STUB_SENTENCES = [
    "Real voices make language feel alive.",
    "Listen closely and follow the rhythm.",
    "Pick a podcast you genuinely enjoy.",
    "Shadow it, record it, and make it yours.",
]


def transcribe(source: str, language: str = "en") -> AsrResult:
    settings = get_settings()
    if settings.asr_backend == "faster_whisper":
        return _faster_whisper(source, language, settings)
    return _stub(language)


def _stub(language: str) -> AsrResult:
    segments: list[AsrSegment] = []
    cursor = 0.0
    for i, sentence in enumerate(_STUB_SENTENCES):
        words = sentence.split()
        per = 0.35
        start = cursor
        tokens = []
        for j, word in enumerate(words):
            tokens.append(AsrWord(
                w=word,
                s=round(start + j * per, 2),
                e=round(start + (j + 1) * per - 0.05, 2),
                p=0.95,
            ))
        end = round(start + len(words) * per + 0.25, 2)
        segments.append(AsrSegment(i, start, end, sentence, tokens))
        cursor = end + 0.2
    return AsrResult(language=language, duration=round(cursor, 2),
                     segments=segments)


# 生产路径的模型实例缓存：(model, device, compute_type) -> WhisperModel。
_MODEL_CACHE: dict[tuple[str, str, str], object] = {}


def _prepare_hf_cache() -> None:
    """让 faster-whisper 从仓库内 .tools/hf-cache 取模型（与字幕工坊一致）。

    必须在 import faster_whisper 前设置；用户显式配置 HF_HOME 时不覆盖。
    """
    if os.environ.get("HF_HOME") or os.environ.get("HUGGINGFACE_HUB_CACHE"):
        return
    os.environ["HF_HOME"] = str(REPO_ROOT / ".tools" / "hf-cache")


def _is_remote(source: str) -> bool:
    return source.startswith("http://") or source.startswith("https://")


def _download_once(url: str, path: str, timeout: float) -> None:
    # 区分连接/读取空闲超时：个别 CDN（如 Hetzner/podigee）会在已建立的
    # 连接上长时间静默，单一总超时无法识别这种卡死。
    to = httpx.Timeout(connect=min(timeout, 20.0), read=min(timeout, 45.0),
                       write=30.0, pool=20.0)
    with httpx.stream("GET", url, follow_redirects=True, timeout=to,
                      headers={"User-Agent": "Mozilla/5.0"}) as resp:
        resp.raise_for_status()
        with open(path, "wb") as f:
            for chunk in resp.iter_bytes(chunk_size=1 << 16):
                if chunk:
                    f.write(chunk)


def _download(source: str, timeout: float, deadline: float = 120.0) -> str:
    """下载远端音频到临时文件，返回本地路径（调用方负责删除）。

    实测个别 CDN（podigee/Hetzner）响应体发送极慢（~25KB/s）甚至在响应头
    返回后长时间静默，且 httpcore 的空闲读超时不会按预期中断。因此把单次
    下载放进子线程，用 join 做硬看门狗（[deadline] 秒，可按网络配置），
    到时直接放弃该次尝试，最多 2 次。每次尝试使用独立临时文件，避免被
    放弃的线程延迟写入造成读写竞争。
    """
    suffix = os.path.splitext(urlparse(source).path)[1] or ".audio"
    last_exc: Exception | None = None
    good_path: str | None = None
    for _attempt in range(2):
        fd, path = tempfile.mkstemp(prefix="mll-asr-", suffix=suffix)
        os.close(fd)
        box: dict[str, BaseException] = {}

        def _work() -> None:
            try:
                _download_once(source, path, timeout)
            except BaseException as exc:  # noqa: BLE001 - reported via box
                box["err"] = exc

        th = threading.Thread(target=_work, daemon=True)
        th.start()
        th.join(deadline)
        if th.is_alive():
            last_exc = TimeoutError(f"download hard deadline {deadline}s")
            continue
        if "err" in box:
            last_exc = Exception(box["err"])
            try:
                os.remove(path)
            except OSError:
                pass
            continue
        good_path = path
        break

    if good_path is not None:
        return good_path
    assert last_exc is not None
    raise last_exc


def _get_model(settings):
    key = (settings.asr_model, settings.asr_device, settings.asr_compute_type)
    model = _MODEL_CACHE.get(key)
    if model is None:
        # 批量抓取时同一进程会连续转录很多单集：按配置缓存模型实例，
        # 避免每个单集都重新加载权重（懒加载，仅生产路径使用）。
        _prepare_hf_cache()
        from faster_whisper import WhisperModel  # imported lazily
        model = WhisperModel(key[0], device=key[1], compute_type=key[2])
        _MODEL_CACHE[key] = model
    return model


def _faster_whisper(source: str, language: str, settings) -> AsrResult:
    model = _get_model(settings)

    local_path = None
    media = source
    if _is_remote(source):
        local_path = _download(
            source, settings.asr_download_timeout_sec,
            settings.asr_download_deadline_sec)
        media = local_path
    try:
        # 参数与桌面字幕工坊 transcriber.py 对齐：
        #  * beam_size=5 提升识别稳定性；
        #  * condition_on_previous_text=False 防止长音频提示词累积导致的
        #    重复幻听与越跑越慢；
        #  * hallucination_silence_threshold 抑制静音段幻听；
        #  * VAD 按口播/播客人声分割。
        # language 显式按单集语种传入（de/en/fr/ja…），保证德语音频产出
        # 德语字幕、法语音频产出法语字幕，而不是统一英文。
        segments_iter, info = model.transcribe(
            media,
            language=language or None,
            word_timestamps=True,
            beam_size=5,
            condition_on_previous_text=False,
            hallucination_silence_threshold=2.0,
            vad_filter=True,
            vad_parameters={
                "min_silence_duration_ms": 500,
                "speech_pad_ms": 400,
                "max_speech_duration_s": float("inf"),
            },
        )
        out: list[AsrSegment] = []
        for i, seg in enumerate(segments_iter):
            words = [
                AsrWord(w=w.word.strip(), s=w.start, e=w.end,
                        p=getattr(w, "probability", None))
                for w in (seg.words or [])
            ]
            out.append(AsrSegment(i, seg.start, seg.end, seg.text.strip(), words))
        return AsrResult(language=info.language, duration=info.duration,
                         segments=out)
    finally:
        if local_path is not None:
            try:
                os.remove(local_path)
            except OSError:
                pass
