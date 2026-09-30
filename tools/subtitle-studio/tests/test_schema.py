# -*- coding: utf-8 -*-
import json
import os
import sys
import tempfile
from types import SimpleNamespace

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from mll_subtitles.schema import (  # noqa: E402
    Segment,
    Transcript,
    Word,
    split_by_word_gaps,
    validate,
)


def _word(text, start, end, prob=0.9):
    # faster-whisper word objects carry a leading space and .probability.
    return SimpleNamespace(word=(" " + text if start > 0 else text),
                           start=start, end=end, probability=prob)


def _seg(start, end, words, text=None):
    return SimpleNamespace(start=start, end=end,
                           text=text if text is not None else
                           " ".join(w.word.strip() for w in words),
                           words=words)


def good_transcript():
    segs = [
        _seg(0.1, 1.2, [_word("Hello", 0.1, 0.5), _word("world.", 0.6, 1.2)]),
        _seg(1.4, 2.3, [_word("Good", 1.4, 1.7), _word("bye.", 1.8, 2.3)]),
    ]
    return Transcript.from_whisper(segs, language="en", media_duration=2.5)


def test_from_whisper_builds_word_bounded_segments():
    t = good_transcript()
    assert t.language == "en"
    assert len(t.segments) == 2
    assert t.segments[0].words[0].w == "Hello"
    assert t.segments[0].start == pytest.approx(0.1)
    assert t.segments[0].end == pytest.approx(1.2)
    assert t.duration >= 2.3
    assert validate(t) == []


def test_chinese_segments_join_without_spaces():
    seg = _seg(0.0, 1.0, [_word("你", 0.0, 0.4), _word("好", 0.5, 1.0)],
               text="你好")
    t = Transcript.from_whisper([seg], language="zh", media_duration=1.1)
    assert t.segments[0].text == "你好"
    assert validate(t) == []


def test_json_roundtrip_matches_app_schema():
    t = good_transcript()
    t.segments[0].translation = "你好世界。"
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "x.mll.json")
        t.save_json(path)
        raw = json.load(open(path, encoding="utf-8"))
        assert raw["version"] == 1
        assert raw["segments"][0]["translation"] == "你好世界。"
        assert set(raw["segments"][0]["words"][0]) == {"w", "s", "e", "p"}
        again = Transcript.load_json(path)
        assert validate(again) == []
        assert again.segments[0].words[1].w == "world."


def test_validate_rejects_bad_timing():
    t = good_transcript()
    # zero-length word
    t.segments[1].words[1].e = t.segments[1].words[1].s
    errors = validate(t)
    assert any("时长为 0" in e for e in errors)

    t2 = good_transcript()
    # backwards timing
    t2.segments[0].words[1].s = 0.1
    assert any("早于前一个词" in e for e in validate(t2))

    t3 = good_transcript()
    # word beyond duration
    t3.segments[1].words[-1].e = 9.9
    assert any("超出总时长" in e for e in validate(t3))


def test_validate_rejects_empty_segments_and_negative_start():
    bad = Transcript(language="en", duration=1.0,
                     segments=[Segment(id=0, start=0.0, end=0.0)])
    errors = validate(bad)
    assert any("没有词" in e for e in errors)

    bad2 = Transcript(language="en", duration=1.0, segments=[])
    assert any("没有任何分句" in e for e in validate(bad2))


def test_validate_rejects_overlapping_segments_and_bad_ids():
    t = good_transcript()
    # Stale-commit split regression: segment 2 starts before segment 1 ends.
    t.segments[1].start = 0.3
    t.segments[1].words[0].s = 0.3
    errors = validate(t)
    assert any("早于上一句结束" in e for e in errors)

    t2 = good_transcript()
    t2.segments[1].id = 5
    assert any("编号不连续" in e for e in validate(t2))


def test_from_whisper_repairs_zero_duration_words():
    # Singing/no-VAD artifact: a word stamped with start == end.
    seg = _seg(10.0, 10.6, [
        _word("so", 10.0, 10.2),
        _word("far", 10.2, 10.2),   # zero duration, same grid point
        _word("away", 10.3, 10.6),
    ])
    t = Transcript.from_whisper([seg], language="en", media_duration=10.8)
    fixed = t.segments[0].words[1]
    assert fixed.e - fixed.s >= 0.001
    assert fixed.s >= t.segments[0].words[0].e
    assert fixed.e <= t.segments[0].words[2].s
    assert validate(t) == []


def test_split_by_word_gaps_cuts_mega_segment_at_pauses():
    # Two lyric lines inside one 30 s no-VAD segment, separated by a 1.2 s
    # pause; within a line words are tightly packed.
    line1 = [_word(t, s, s + 0.4) for t, s in
             (("My", 0.0), ("love", 0.5), ("forever", 1.0))]
    line2 = [_word(t, s, s + 0.4) for t, s in
             (("where", 2.6), ("skies", 3.1), ("blue", 3.6))]
    seg = _seg(0.0, 4.0, line1 + line2)
    t = Transcript.from_whisper([seg], language="en", media_duration=4.2)
    cut = split_by_word_gaps(t)
    assert len(cut.segments) == 2
    assert [w.w for w in cut.segments[0].words] == ["My", "love", "forever"]
    assert [w.w for w in cut.segments[1].words] == ["where", "skies", "blue"]
    assert [s.id for s in cut.segments] == [0, 1]
    assert validate(cut) == []


def test_split_by_word_gaps_leaves_tight_speech_untouched():
    seg = _seg(0.0, 1.6, [
        _word("real", 0.0, 0.4), _word("voices", 0.5, 1.0),
        _word("now", 1.1, 1.6)])
    t = Transcript.from_whisper([seg], language="en", media_duration=1.8)
    assert len(split_by_word_gaps(t).segments) == 1


def test_recompute_bounds_after_edit():
    t = good_transcript()
    # Merge a new word into the first segment and recompute.
    t.segments[0].words.append(Word("there", 1.25, 1.35))
    t.segments[0].text = ""
    t.recompute_bounds()
    assert t.segments[0].end == pytest.approx(1.35)
    assert t.segments[0].text.endswith("there")
    assert [s.id for s in t.segments] == [0, 1]
    assert validate(t) == []
