"""Pluggable translation provider.

MVP stub marks strings with a tag so end-to-end flows work without API keys.
The MyMemory provider gives real keyless machine translation (free anonymous
quota ~5k chars/day; set MLL_TRANSLATOR_EMAIL to raise it). Wire the backend
in main.py based on settings.translate_backend.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Protocol


class TranslateProvider(Protocol):
    def translate(self, texts: list[str], source: str, target: str) -> list[str]:
        ...


class StubTranslateProvider:
    def translate(self, texts, source, target):
        tag = {"zh": "【译】", "en": "[tr] ", "ja": "【訳】"}.get(target, "[tr] ")
        return [f"{tag}{t}" for t in texts]


class MyMemoryTranslateProvider:
    """Real translation via api.mymemory.translated.net (no API key needed).

    Per-sentence failures become empty strings instead of raising, so one
    untranslatable sentence never blocks a whole episode; the pipeline then
    simply keeps that sentence source-only.
    """

    def __init__(self, pause: float = 0.3, timeout: float = 12.0):
        self._pause = pause
        self._timeout = timeout

    @staticmethod
    def _code(code: str) -> str:
        code = (code or "").strip().lower()
        if code.startswith("zh"):
            return "zh-CN"
        return code.split("-")[0]

    def _one(self, text: str, source: str, target: str) -> str:
        url = ("https://api.mymemory.translated.net/get?"
               + urllib.parse.urlencode(
                   {"q": text, "langpair": f"{source}|{target}"}))
        email = os.environ.get("MLL_TRANSLATOR_EMAIL")
        if email:
            url += "&de=" + urllib.parse.quote(email)
        req = urllib.request.Request(
            url, headers={"User-Agent": "MyLangLean-Server/1.0"})
        with urllib.request.urlopen(req, timeout=self._timeout) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
        if data.get("quotaFinished"):
            raise RuntimeError("MyMemory daily quota finished")
        translated = (data.get("responseData") or {}).get("translatedText") or ""
        status = data.get("responseStatus")
        if (not isinstance(status, int) or status >= 400
                or not translated
                or translated.startswith("MYMEMORY WARNING")):
            raise RuntimeError(f"MyMemory bad response status={status}")
        return translated.strip()

    def translate(self, texts, source, target):
        src = self._code(source)
        tgt = self._code(target)
        out: list[str] = []
        for i, text in enumerate(texts):
            text = (text or "").strip()
            if not text:
                out.append("")
                continue
            try:
                out.append(self._one(text, src, tgt))
            except (urllib.error.URLError, TimeoutError, ValueError,
                    RuntimeError):
                out.append("")
            if i < len(texts) - 1 and self._pause:
                time.sleep(self._pause)
        return out


_provider: TranslateProvider = StubTranslateProvider()


def set_translate_provider(provider: TranslateProvider) -> None:
    global _provider
    _provider = provider


def translate(texts: list[str], source: str, target: str) -> list[str]:
    return _provider.translate(texts, source, target)
