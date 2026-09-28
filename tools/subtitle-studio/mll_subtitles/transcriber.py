# -*- coding: utf-8 -*-
"""
faster-whisper wrapper. Decodes audio and video directly via PyAV (bundled
with faster-whisper), so no external ffmpeg binary is needed.
"""
from __future__ import annotations

import os
from typing import Callable, List, Optional

try:
    from .schema import Transcript
except ImportError:  # direct script launch (python mll_subtitles/transcriber.py)
    from schema import Transcript

# Keep the model cache inside the repo (.tools/hf-cache) unless the user has
# configured HF_HOME/HF_HUB_CACHE explicitly. Must be set before
# faster_whisper/huggingface_hub are imported.
_REPO_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", ".."))
if not os.environ.get("HF_HOME") and not os.environ.get("HUGGINGFACE_HUB_CACHE"):
    os.environ["HF_HOME"] = os.path.join(_REPO_ROOT, ".tools", "hf-cache")

# Default to the China-accessible HuggingFace mirror; users can override by
# setting HF_ENDPOINT before launching.
os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")

MODEL_SIZES = ("tiny", "base", "small", "medium", "large-v3")

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
    try:
        segments_iter, info = model.transcribe(
            media_path,
            language=(language or None),
            word_timestamps=True,
            vad_filter=True,
            vad_parameters={"min_silence_duration_ms": 500},
            beam_size=5,
        )
        log(f"检测语言：{info.language}（置信度 {info.language_probability:.2f}），"
            f"时长 {info.duration:.1f}s")

        materialised: List = []
        for i, seg in enumerate(segments_iter, 1):
            materialised.append(seg)
            log(f"  句 {i}: [{seg.start:6.2f}-{seg.end:6.2f}] "
                f"{seg.text.strip()}")
    except Exception as e:
        raise RuntimeError(
            f"无法解码该音视频（请确认文件包含音轨且格式/编码受支持）：{media_path}\n"
            f"原始错误：{e}") from e

    transcript = Transcript.from_whisper(
        materialised,
        language=info.language,
        media_duration=info.duration,
    )
    log(f"识别完成：{len(transcript.segments)} 句")
    return transcript
