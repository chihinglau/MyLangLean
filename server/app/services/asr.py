"""ASR abstraction.

Production uses faster-whisper with word_timestamps=True. When the heavy
dependency / model is unavailable (dev laptop), the stub backend returns a
deterministic word-level transcript so the whole client flow can be tested.
"""
from __future__ import annotations

from dataclasses import dataclass

from ..core.config import get_settings


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


def _faster_whisper(source: str, language: str, settings) -> AsrResult:  # pragma: no cover
    from faster_whisper import WhisperModel  # imported lazily

    model = WhisperModel(
        settings.asr_model,
        device=settings.asr_device,
        compute_type=settings.asr_compute_type,
    )
    segments_iter, info = model.transcribe(
        source,
        language=language or None,
        word_timestamps=True,
        vad_filter=True,
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
