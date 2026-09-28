# -*- coding: utf-8 -*-
"""
Word-level transcript schema shared with the Flutter app.

JSON layout (version 1, consumed by Transcript.fromJson in app/lib):

    {
      "version": 1,
      "language": "en",
      "duration": 12.34,
      "segments": [
        {"id": 0, "start": 0.1, "end": 2.3, "text": "...",
         "translation": "...",            # optional
         "words": [{"w": "Hi", "s": 0.1, "e": 0.35, "p": 0.91}, ...]}
      ]
    }

Times are seconds (float). All model classes are mutable so the GUI can
edit them; call :func:`validate` before export.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from typing import Any, Iterable, List, Optional

SCHEMA_VERSION = 1
TIME_EPS = 0.02  # seconds of tolerance for duration checks


@dataclass
class Word:
    w: str
    s: float
    e: float
    p: Optional[float] = None

    def to_json(self) -> dict:
        d = {"w": self.w, "s": round(float(self.s), 3), "e": round(float(self.e), 3)}
        if self.p is not None:
            d["p"] = round(float(self.p), 3)
        return d

    @classmethod
    def from_json(cls, d: dict) -> "Word":
        return cls(w=str(d["w"]), s=float(d["s"]), e=float(d["e"]),
                   p=(float(d["p"]) if d.get("p") is not None else None))


@dataclass
class Segment:
    id: int
    start: float
    end: float
    text: str = ""
    translation: Optional[str] = None
    words: List[Word] = field(default_factory=list)

    def to_json(self) -> dict:
        d: dict[str, Any] = {
            "id": int(self.id),
            "start": round(float(self.start), 3),
            "end": round(float(self.end), 3),
            "text": self.text,
            "words": [w.to_json() for w in self.words],
        }
        if self.translation is not None and self.translation != "":
            d["translation"] = self.translation
        return d

    def recompute_text(self, language: str) -> None:
        """Rebuild the display text after words were edited."""
        if language and language.lower() in {"zh", "ja", "ko", "th"}:
            self.text = "".join(w.w for w in self.words)
        else:
            self.text = " ".join(w.w for w in self.words)

    @classmethod
    def from_json(cls, d: dict) -> "Segment":
        return cls(
            id=int(d["id"]),
            start=float(d["start"]),
            end=float(d["end"]),
            text=str(d.get("text", "")),
            translation=d.get("translation"),
            words=[Word.from_json(w) for w in d.get("words", [])],
        )


@dataclass
class Transcript:
    language: str = "en"
    duration: float = 0.0
    segments: List[Segment] = field(default_factory=list)
    version: int = SCHEMA_VERSION

    # ---------------------------------------------------------------- builders

    @classmethod
    def from_whisper(
        cls,
        whisper_segments: Iterable,
        language: str,
        media_duration: Optional[float] = None,
    ) -> "Transcript":
        """Convert faster-whisper segments (objects with .start/.end/.text/
        .words) into the app schema. Word timestamps drive segment bounds so
        karaoke highlight cannot drift from the words."""
        segments: list[Segment] = []
        last_end = 0.0
        for idx, seg in enumerate(whisper_segments):
            raw_words = getattr(seg, "words", None) or []
            words: list[Word] = []
            for ww in raw_words:
                text = (getattr(ww, "word", None) or "").strip()
                if not text:
                    continue
                prob = getattr(ww, "probability", None)
                words.append(Word(
                    w=text,
                    s=float(ww.start),
                    e=float(ww.end),
                    p=(float(prob) if prob is not None else None),
                ))
            if not words:
                continue
            start = words[0].s
            end = words[-1].e
            last_end = max(last_end, end)
            segments.append(Segment(
                id=idx,
                start=start,
                end=end,
                text=(getattr(seg, "text", None) or _join_words(words, language)).strip(),
                words=words,
            ))
        _renumber(segments)
        duration = max(float(media_duration or 0.0), last_end + 0.02)
        return cls(language=language, duration=round(duration, 3),
                   segments=segments)

    # ------------------------------------------------------------ serialize

    def to_json(self) -> dict:
        return {
            "version": self.version,
            "language": self.language,
            "duration": round(float(self.duration), 3),
            "segments": [s.to_json() for s in self.segments],
        }

    def save_json(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(self.to_json(), f, ensure_ascii=False, indent=2)
            f.write("\n")

    @classmethod
    def load_json(cls, path: str) -> "Transcript":
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return cls(
            version=int(data.get("version", SCHEMA_VERSION)),
            language=str(data.get("language", "en")),
            duration=float(data.get("duration", 0.0)),
            segments=[Segment.from_json(s) for s in data.get("segments", [])],
        )

    # -------------------------------------------------------------- editing

    def recompute_bounds(self) -> None:
        """Recompute segment bounds from their words, ids, and total duration.
        Call after any edit in the GUI."""
        self.segments = [s for s in self.segments if s.words]
        last = 0.0
        for seg in self.segments:
            seg.start = seg.words[0].s
            seg.end = seg.words[-1].e
            if not seg.text.strip():
                seg.text = _join_words(seg.words, self.language)
            last = max(last, seg.end)
        _renumber(self.segments)
        self.duration = round(max(self.duration, last + 0.02), 3)


def _renumber(segments: List[Segment]) -> None:
    for i, s in enumerate(segments):
        s.id = i


def _join_words(words: List[Word], language: str) -> str:
    # Whisper emits tokens with leading spaces for space-delimited languages.
    # For zh/ja/ko/th tokens are typically written without spaces.
    if language and language.lower() in {"zh", "ja", "ko", "th"}:
        return "".join(w.w for w in words)
    return " ".join(w.w for w in words)


# ----------------------------------------------------------------- validation

_WORD_RE = re.compile(r"[^0-9a-z\u4e00-\u9fff']")


def _norm(text: str) -> str:
    return _WORD_RE.sub("", text.lower())


def validate(transcript: Transcript) -> List[str]:
    """Return a list of human-readable (Chinese) problems. Empty = valid."""
    errors: list[str] = []
    if not transcript.language.strip():
        errors.append("语言代码为空")
    if not transcript.segments:
        errors.append("没有任何分句")
        return errors
    if transcript.duration <= 0:
        errors.append("总时长必须大于 0")

    prev_seg_start = -1.0
    prev_seg_end = -1.0
    for idx, seg in enumerate(transcript.segments):
        tag = f"第 {idx + 1} 句"
        if seg.id != idx:
            errors.append(f"{tag} id={seg.id}，应为 {idx}（分句编号不连续）")
        if not seg.words:
            errors.append(f"{tag} 没有词")
            continue
        if seg.start < -TIME_EPS:
            errors.append(f"{tag} 开始时间为负")
        prev = -1.0
        for i, word in enumerate(seg.words):
            where = f"{tag} 第 {i + 1} 个词「{word.w}」"
            if not word.w.strip():
                errors.append(f"{where} 文本为空")
            if word.e - word.s < 0.001:
                errors.append(f"{where} 时长为 0 或为负（{word.s:.3f}→{word.e:.3f}）")
            if word.s + TIME_EPS < prev:
                errors.append(f"{where} 开始时间早于前一个词（{word.s:.3f}）")
            prev = word.e
            if word.e > transcript.duration + TIME_EPS:
                errors.append(
                    f"{where} 结束时间 {word.e:.3f}s 超出总时长 "
                    f"{transcript.duration:.3f}s")
        if abs(seg.words[0].s - seg.start) > TIME_EPS:
            errors.append(f"{tag} 句开始（{seg.start:.3f}）与首词不一致")
        if abs(seg.words[-1].e - seg.end) > TIME_EPS:
            errors.append(f"{tag} 句结束（{seg.end:.3f}）与末词不一致")
        if seg.start + TIME_EPS < prev_seg_start:
            errors.append(f"{tag} 开始时间早于前一句")
        if idx > 0 and seg.words[0].s + TIME_EPS < prev_seg_end:
            errors.append(
                f"{tag} 首词开始于 {seg.words[0].s:.3f}s，"
                f"早于上一句结束 {prev_seg_end:.3f}s（分句重叠会导致高亮串行）")
        prev_seg_start = seg.start
        prev_seg_end = seg.end
    return errors
