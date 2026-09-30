# -*- coding: utf-8 -*-
"""
faster-whisper wrapper. Decodes audio and video directly via PyAV (bundled
with faster-whisper), so no external ffmpeg binary is needed.
"""
from __future__ import annotations

import os
import sys
from typing import Callable, List, Optional

try:
    from .schema import Transcript, split_by_word_gaps
except ImportError:  # direct script launch (python mll_subtitles/transcriber.py)
    from schema import Transcript, split_by_word_gaps


def _writable_dir(path: str) -> bool:
    try:
        os.makedirs(path, exist_ok=True)
        probe = os.path.join(path, ".write-probe")
        with open(probe, "w", encoding="utf-8") as f:
            f.write("ok")
        os.remove(probe)
        return True
    except OSError:
        return False


def _default_hf_cache() -> str:
    """Where Whisper models live.

    * Source checkout: inside the repo at ``.tools/hf-cache``.
    * Frozen exe (PyInstaller): a portable ``hf-cache`` folder next to the
      exe when that directory is writable, otherwise a per-user folder under
      LOCALAPPDATA (covers installs under Program Files).
    """
    if getattr(sys, "frozen", False):
        exe_dir = os.path.dirname(os.path.abspath(sys.executable))
        portable = os.path.join(exe_dir, "hf-cache")
        if _writable_dir(portable):
            return portable
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
        return os.path.join(base, "MyLangLeanSubtitleStudio", "hf-cache")
    repo_root = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    return os.path.join(repo_root, ".tools", "hf-cache")


# Keep the model cache in a known local folder unless the user has
# configured HF_HOME/HUGGINGFACE_HUB_CACHE explicitly. Must be set before
# faster_whisper/huggingface_hub are imported.
_HF_HOME = os.environ.get("HF_HOME")
if not _HF_HOME and not os.environ.get("HUGGINGFACE_HUB_CACHE"):
    _HF_HOME = _default_hf_cache()
    os.environ["HF_HOME"] = _HF_HOME
# hf_xet otherwise scribbles a <drive>:\hf_cache tree at import time; keep
# its cache/log folder under the effective HF home. Env names come from the
# hf-xet native extension (HF_XET_CACHE / HF_XET_LOG_DIR).
os.environ.setdefault("HF_XET_CACHE", os.path.join(_HF_HOME, "xet"))
os.environ.setdefault("HF_XET_LOG_DIR", os.path.join(_HF_HOME, "xet", "logs"))

# Default to the China-accessible HuggingFace mirror; users can override by
# setting HF_ENDPOINT before launching.
os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")

MODEL_SIZES = ("tiny", "base", "small", "medium", "large-v3")

# Style hint for the no-VAD fallback (song / heavy background music). Sung
# opening verses over a soft intro are otherwise collapsed or skipped by the
# model; a generic music prompt restores them. Kept free of any real lyrics so
# it cannot inject words, and only languages with a translated hint get one.
_MUSIC_PROMPTS = {
    "en": "[music] Song lyrics with singing vocals:",
    "zh": "（音乐）歌曲演唱歌词：",
    "ja": "（音楽）歌の歌詞：",
    "ko": "(음악) 노래 가사:",
    "fr": "[musique] Paroles de chanson chantées :",
    "de": "[Musik] Liedtext mit Gesang:",
    "es": "[música] Letra de canción con voz cantada:",
    "ru": "[музыка] Текст песни с вокалом:",
}

LogFn = Callable[[str], None]


def _default_log(msg: str) -> None:
    print(msg, flush=True)


def transcribe_file(
    media_path: str,
    model_size: str = "small",
    language: Optional[str] = None,
    compute_type: str = "int8",
    device: str = "cpu",
    log: LogFn = _default_log,
) -> Transcript:
    """Transcribe one media file into a word-level :class:`Transcript`."""
    from faster_whisper import WhisperModel

    if model_size not in MODEL_SIZES:
        raise ValueError(f"不支持的模型档位: {model_size}")

    log(f"加载模型 {model_size}（首次运行会自动下载，请稍候）…")
    model = WhisperModel(model_size, device=device, compute_type=compute_type)

    log(f"开始识别：{media_path}")
    # No artificial duration cap: the whole file is always processed
    # (clip_timestamps="0"). Two stability measures for long media:
    #   * condition_on_previous_text=False stops prompt accumulation that
    #     makes long runs progressively slower and triggers repetition loops;
    #   * hallucination_silence_threshold drops phantom repetition over
    #     music/silence.
    # Pass 1 runs Silero VAD (great for speech/podcasts). Sung vocals over a
    # mastered mix can fool the VAD into treating most of the track as
    # "not speech", which previously looked like the tool only handling the
    # first ~1 minute. When VAD coverage is poor we automatically re-run on
    # the full stream without VAD, so songs / heavy-background-audio are not
    # truncated.
    common_kw = dict(
        language=(language or None),
        word_timestamps=True,
        beam_size=5,
        clip_timestamps="0",
        condition_on_previous_text=False,
        hallucination_silence_threshold=2.0,
    )

    def _run(use_vad: bool, tag: str, prompt_language: Optional[str] = None):
        log(f"识别通道：{tag}")
        kwargs = dict(common_kw)
        if use_vad:
            kwargs.update(vad_filter=True, vad_parameters={
                "min_silence_duration_ms": 500,
                "speech_pad_ms": 400,
                "max_speech_duration_s": float("inf"),
            })
        else:
            kwargs.update(vad_filter=False)
            # The VAD pass already detected the language; pin it so the
            # fallback cannot re-detect differently on instrumental passages.
            if prompt_language:
                kwargs["language"] = prompt_language
                # Singing recall hint; never used on the normal speech path.
                prompt = _MUSIC_PROMPTS.get(prompt_language.lower())
                if prompt:
                    kwargs["initial_prompt"] = prompt
        try:
            segments_iter, meta = model.transcribe(media_path, **kwargs)
            rows: List = []
            total = max(float(meta.duration or 0.0), 0.001)
            for i, seg in enumerate(segments_iter, 1):
                rows.append(seg)
                log(f"  句 {i}: [{seg.start:6.2f}-{seg.end:6.2f}] "
                    f"({seg.end / total * 100:5.1f}%) {seg.text.strip()}")
            return rows, meta
        except Exception as e:
            raise RuntimeError(
                f"无法解码该音视频（请确认文件包含音轨且格式/编码受支持）：{media_path}\n"
                f"原始错误：{e}") from e

    try:
        rows, info = _run(True, "VAD 人声分割（适合口播/播客）")
        mins, secs = divmod(info.duration, 60)
        log(f"检测语言：{info.language}（置信度 {info.language_probability:.2f}），"
            f"总时长 {info.duration:.1f}s（{int(mins)}分{int(secs)}秒），"
            "无时长上限，整段音频都会识别（CPU 上耗时约与音频等长，请耐心等待）")

        last_end = max((r.end for r in rows), default=0.0)
        coverage = last_end / max(float(info.duration or 0.0), 0.001)
        used_vad = True
        # Coverage fallback: below 60 % of the timeline for files >= 20 s means
        # VAD likely swallowed whole vocal passages (typical for songs).
        if info.duration >= 20.0 and coverage < 0.6:
            log(f"⚠ VAD 只识别到 {coverage*100:.0f}% 的时长（常见于歌曲/强背景音乐，"
                "人声被误判为非人声）。自动改用全音频识别以保证不丢内容，"
                "耗时会更长一些…")
            rows2, info2 = _run(False,
                                "全音频识别（无 VAD，兜底歌曲/强背景音乐）",
                                prompt_language=(language or info.language))
            last_end2 = max((r.end for r in rows2), default=0.0)
            if last_end2 > last_end:
                rows, info = rows2, info2
                used_vad = False
                log(f"已采用全音频识别结果：覆盖到 {last_end2:.1f}s / "
                    f"{info.duration:.1f}s。")
            else:
                log("全音频结果覆盖更差，保留 VAD 结果。")
    except RuntimeError:
        raise

    transcript = Transcript.from_whisper(
        rows,
        language=info.language,
        media_duration=info.duration,
    )
    if not used_vad:
        # No-VAD mode can produce 30 s mega-segments for singing; re-cut them
        # at clear pauses between words so lyrics stay line-sized.
        before = len(transcript.segments)
        transcript = split_by_word_gaps(transcript)
        log(f"按词间停顿整理分句：{before} 句 → {len(transcript.segments)} 句")
    log(f"识别完成：{len(transcript.segments)} 句，覆盖至 "
        f"{transcript.duration:.1f}s")
    return transcript
