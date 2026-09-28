"""Pluggable translation provider.

MVP stub marks strings with a tag so end-to-end flows work without API keys.
Real deployment implements TranslateProvider against DeepL / a hosted LLM /
an in-house model; wire it in main.py via dependency override.
"""
from __future__ import annotations

from typing import Protocol


class TranslateProvider(Protocol):
    def translate(self, texts: list[str], source: str, target: str) -> list[str]:
        ...


class StubTranslateProvider:
    def translate(self, texts, source, target):
        tag = {"zh": "【译】", "en": "[tr] ", "ja": "【訳】"}.get(target, "[tr] ")
        return [f"{tag}{t}" for t in texts]


_provider: TranslateProvider = StubTranslateProvider()


def set_translate_provider(provider: TranslateProvider) -> None:
    global _provider
    _provider = provider


def translate(texts: list[str], source: str, target: str) -> list[str]:
    return _provider.translate(texts, source, target)
