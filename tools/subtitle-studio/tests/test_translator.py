# -*- coding: utf-8 -*-
"""Translator unit tests. No real network: providers are fakes or the HTTP
transport is monkeypatched with canned JSON."""
import json
import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from mll_subtitles import translator  # noqa: E402
from mll_subtitles.schema import Transcript  # noqa: E402
from mll_subtitles.translator import (  # noqa: E402
    TranslationError,
    normalize_lang,
    parse_google_response,
    translate_text,
    translate_transcript,
)


def _transcript(n=3, language="en"):
    from mll_subtitles.schema import Segment, Word
    if language == "zh":
        src = [("你好。", 0.0, 1.0), ("世界。", 1.0, 2.0), ("再见。", 2.0, 3.0)]
    else:
        src = [("Hello there.", 0.0, 1.0), ("How are you?", 1.0, 2.0),
               ("Goodbye now.", 2.0, 3.0)]
    return Transcript(
        language=language, duration=10.0,
        segments=[Segment(id=i, start=s, end=e,
                          words=[Word(text, s, e, 0.9)], text=text)
                  for i, (text, s, e) in enumerate(src[:n])])


def test_normalize_lang_aliases():
    assert normalize_lang("zh") == "zh-CN"
    assert normalize_lang("ZH_Hans") == "zh-CN"
    assert normalize_lang("zh-TW") == "zh-TW"
    assert normalize_lang("en-US") == "en"
    assert normalize_lang("ja") == "ja"
    assert normalize_lang(None) == "auto"
    assert normalize_lang("") == "auto"


def test_parse_google_response_joins_chunks():
    body = json.dumps(
        [[["你好，", "Hello,", None, None, 10],
          ["世界。", "world.", None, None, 5]], None, "en"])
    assert parse_google_response(body) == "你好，世界。"
    with pytest.raises(TranslationError):
        parse_google_response(json.dumps([[[]], None]))


def test_mymemory_provider_parses_response(monkeypatch):
    payload = {"responseData": {"translatedText": "你好世界。"},
               "responseStatus": 200, "quotaFinished": False}
    calls = {}

    def fake_get(url):
        calls["url"] = url
        return 200, json.dumps(payload)

    monkeypatch.setattr(translator, "_http_get", fake_get)
    out = translator.mymemory_provider("Hello world.", "en", "zh-CN")
    assert out == "你好世界。"
    assert "langpair=en%7Czh-CN" in calls["url"] or "langpair=en|zh-CN" in calls["url"]

    payload["quotaFinished"] = True
    with pytest.raises(TranslationError, match="额度"):
        translator.mymemory_provider("x", "en", "zh-CN")

    payload.update(quotaFinished=False, responseStatus=403)
    with pytest.raises(TranslationError):
        translator.mymemory_provider("x", "en", "zh-CN")


def test_translate_text_falls_back_across_providers():
    calls = []

    def bad(text, src, tgt):
        calls.append("bad")
        raise TranslationError("nope")

    def good(text, src, tgt):
        calls.append("good")
        return "译:" + text

    assert translate_text("Hi", "en", "zh-CN", providers=[bad, good]) == "译:Hi"
    # each provider is retried (_RETRIES=2) before falling back
    assert calls == ["bad", "bad", "good"]

    with pytest.raises(TranslationError, match="所有翻译通道均失败"):
        translate_text("Hi", "en", "zh-CN", providers=[bad])


def test_translate_text_retries_then_succeeds(monkeypatch):
    attempts = {"n": 0}
    monkeypatch.setattr(translator.time, "sleep", lambda _s: None)

    def flaky(text, src, tgt):
        attempts["n"] += 1
        if attempts["n"] == 1:
            raise TranslationError("transient")
        return "OK"

    assert translate_text("x", "en", "zh-CN", providers=[flaky]) == "OK"
    assert attempts["n"] == 2


def test_translate_transcript_fills_skips_and_overwrites():
    t = _transcript()
    t.segments[1].translation = "人工译文"
    logs = []

    def fake(text, src, tgt):
        return "[Z]" + text

    done, already, failed = translate_transcript(
        t, "zh-CN", providers=[fake], log=logs.append, pause=0)
    assert done == 2 and already == 1 and failed == []
    assert t.segments[0].translation == "[Z]Hello there."
    assert t.segments[1].translation == "人工译文"  # manual text preserved
    assert t.segments[2].translation == "[Z]Goodbye now."

    # Second run without force translates nothing.
    done2, already2, failed2 = translate_transcript(
        t, "zh-CN", providers=[fake], log=logs.append, pause=0)
    assert (done2, already2, failed2) == (0, 3, [])

    # force=True re-translates every sentence.
    done3, already3, _ = translate_transcript(
        t, "zh-CN", force=True, providers=[fake], log=logs.append, pause=0)
    assert done3 == 3 and already3 == 0
    assert t.segments[1].translation == "[Z]How are you?"


def test_translate_transcript_records_failures_and_keeps_partial(monkeypatch):
    monkeypatch.setattr(translator.time, "sleep", lambda _s: None)
    t = _transcript()

    def flaky(text, src, tgt):
        if text.startswith("How"):
            raise TranslationError("boom")
        return "[Z]" + text

    done, already, failed = translate_transcript(
        t, "zh-CN", providers=[flaky], log=lambda _m: None, pause=0)
    assert done == 2
    assert failed == [t.segments[1].id]
    assert t.segments[1].translation is None  # untouched on failure
    assert t.segments[0].translation is not None


def test_translate_transcript_rejects_same_language():
    t = _transcript(language="zh")
    with pytest.raises(TranslationError, match="相同"):
        translate_transcript(t, "zh", providers=[lambda *_: "x"], pause=0)
    with pytest.raises(TranslationError):
        translate_transcript(t, "zh-Hans", providers=[lambda *_: "x"], pause=0)
    # auto-detected transcript must not be blocked (language unknown yet).
    t2 = _transcript(language=None)
    done, _, failed = translate_transcript(
        t2, "zh-CN", providers=[lambda text, s, g: "[Z]" + text], pause=0)
    assert done == 3 and failed == []
