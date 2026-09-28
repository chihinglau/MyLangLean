# -*- coding: utf-8 -*-
"""
Machine translation for transcript segments.

The studio ships with free, keyless providers so translation works out of the
box (verified from a China network):

* ``mymemory``   - api.mymemory.translated.net (default; reachable without a proxy)
* ``google``     - translate.googleapis.com gtx endpoint (works overseas)
* ``libre``      - any LibreTranslate instance (MLL_LIBRETRANSLATE_URL)

All HTTP uses the standard library only. Providers are plain callables so the
unit tests / GUI smoke can inject fakes without touching the network.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Callable, List, Optional, Tuple

try:
    from .schema import Transcript
except ImportError:  # direct script launch
    from schema import Transcript

LogFn = Callable[[str], None]

# Provider name -> translate(text, source, target) -> translated text
Provider = Callable[[str, str, str], str]

_TIMEOUT = 12
_RETRIES = 2
_USER_AGENT = "MyLangLean-SubtitleStudio/1.0"

# Canonicalise the handful of codes Whisper / the app actually emits.
_ALIASES = {
    "zh": "zh-CN", "zh-cn": "zh-CN", "zh-hans": "zh-CN", "cn": "zh-CN",
    "zh-hant": "zh-TW", "zh-tw": "zh-TW", "tw": "zh-TW",
    "en": "en", "en-us": "en", "ja": "ja", "ko": "ko",
    "fr": "fr", "de": "de", "es": "es", "ru": "ru", "it": "it",
    "pt": "pt", "th": "th", "vi": "vi", "ar": "ar",
}


class TranslationError(RuntimeError):
    """All configured providers failed (or arguments were invalid)."""


def normalize_lang(code: Optional[str]) -> str:
    """Map a Whisper/app language code to a canonical BCP-47-ish tag."""
    if not code:
        return "auto"
    key = str(code).strip().lower().replace("_", "-")
    return _ALIASES.get(key, key.split("-")[0])


def _http_get(url: str) -> Tuple[int, str]:
    req = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
        return resp.getcode(), resp.read().decode("utf-8", "replace")


def _http_post(url: str, payload: dict, api_key: Optional[str] = None) -> str:
    headers = {"User-Agent": _USER_AGENT,
               "Content-Type": "application/json"}
    if api_key:
        headers["api-key"] = api_key
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
        return resp.read().decode("utf-8", "replace")


# ------------------------------------------------------------- providers

def mymemory_provider(text: str, source: str, target: str) -> str:
    """Anonymous MyMemory endpoint. Set MLL_TRANSLATOR_EMAIL to lift the
    anonymous daily quota (5k chars/day -> 50k)."""
    src = "zh-CN" if source.startswith("zh") else source
    tgt = "zh-CN" if target.startswith("zh") else target
    url = ("https://api.mymemory.translated.net/get?"
           + urllib.parse.urlencode({"q": text, "langpair": f"{src}|{tgt}"}))
    email = os.environ.get("MLL_TRANSLATOR_EMAIL")
    if email:
        url += "&de=" + urllib.parse.quote(email)
    code, body = _http_get(url)
    data = json.loads(body)
    if data.get("quotaFinished"):
        raise TranslationError("MyMemory 当日匿名额度已用完"
                               "（可设置环境变量 MLL_TRANSLATOR_EMAIL 提高额度）")
    status = data.get("responseStatus")
    translated = (data.get("responseData") or {}).get("translatedText") or ""
    if code != 200 or not isinstance(status, int) or status >= 400 or not translated:
        raise TranslationError(
            f"MyMemory 返回异常（status={status}）：{data.get('responseDetails')}")
    # MYMEMORY WARNING strings come back when it could not MT the sentence.
    if translated.startswith("MYMEMORY WARNING"):
        raise TranslationError("MyMemory 无法翻译该句：" + translated[:120])
    return translated.strip()


def google_provider(text: str, source: str, target: str) -> str:
    """Keyless google-translate web endpoint (``client=gtx``)."""
    tgt = "zh-CN" if target == "zh-CN" else target
    url = ("https://translate.googleapis.com/translate_a/single?"
           + urllib.parse.urlencode(
               {"client": "gtx", "sl": source or "auto",
                "tl": tgt, "dt": "t", "q": text}))
    _, body = _http_get(url)
    return parse_google_response(body)


def parse_google_response(body: str) -> str:
    """Join the text chunks of a gtx response: [[[translated, original,...]]]."""
    data = json.loads(body)
    chunks = []
    for row in (data[0] if data and data[0] else []):
        if row and row[0]:
            chunks.append(row[0])
    out = "".join(chunks).strip()
    if not out:
        raise TranslationError("Google 端点返回了空译文")
    return out


def libre_provider(text: str, source: str, target: str) -> str:
    """Self-hostable LibreTranslate. Requires MLL_LIBRETRANSLATE_URL;
    optional MLL_LIBRETRANSLATE_KEY for locked instances."""
    base = os.environ.get("MLL_LIBRETRANSLATE_URL", "").rstrip("/")
    if not base:
        raise TranslationError("未配置 MLL_LIBRETRANSLATE_URL")
    # LibreTranslate uses plain "zh" rather than zh-CN.
    src = "zh" if source.startswith("zh") else source
    tgt = "zh" if target.startswith("zh") else target
    body = _http_post(
        base + "/translate",
        {"q": text, "source": src or "auto", "target": tgt,
         "format": "text"},
        api_key=os.environ.get("MLL_TRANSLATE_KEY"),
    )
    out = (json.loads(body) or {}).get("translatedText", "").strip()
    if not out:
        raise TranslationError("LibreTranslate 返回了空译文")
    return out


PROVIDERS: dict[str, Provider] = {
    "mymemory": mymemory_provider,
    "google": google_provider,
    "gtx": google_provider,
    "libre": libre_provider,
    "libretranslate": libre_provider,
}


def default_provider_names() -> List[str]:
    names = [n.strip() for n in
             os.environ.get("MLL_TRANSLATE_PROVIDER", "mymemory,google").split(",")
             if n.strip()]
    if os.environ.get("MLL_LIBRETRANSLATE_URL") and "libre" not in names:
        names.append("libre")
    return names


def translate_text(
    text: str,
    source: str,
    target: str,
    providers: Optional[List[Provider]] = None,
) -> str:
    """Translate one string, trying each provider with retries. Raises
    TranslationError only when every provider failed."""
    chain = providers or [PROVIDERS[n] for n in default_provider_names()]
    errors: list[str] = []
    for fn in chain:
        for attempt in range(1, _RETRIES + 1):
            try:
                out = fn(text, source, target)
                if out and out.strip():
                    return out.strip()
                errors.append(f"{fn.__name__}: 空译文")
            except (urllib.error.URLError, urllib.error.HTTPError,
                    TimeoutError, TranslationError, ValueError) as e:
                errors.append(f"{getattr(fn, '__name__', fn)}: {e}")
                if attempt < _RETRIES:
                    time.sleep(0.6 * attempt)
    raise TranslationError("所有翻译通道均失败：" + " | ".join(errors[-4:]))


def translate_transcript(
    transcript: Transcript,
    target_lang: str,
    *,
    force: bool = False,
    providers: Optional[List[Provider]] = None,
    log: LogFn = print,
    pause: float = 0.4,
) -> Tuple[int, int, List[int]]:
    """Fill ``segment.translation`` for every segment in place.

    :param force: re-translate sentences that already have a translation
    :param pause: polite delay between network calls
    :returns: (translated_now, already_present, failed_segment_ids)
    """
    target = normalize_lang(target_lang)
    source = normalize_lang(transcript.language)
    if target != "auto" and source != "auto" and source == target:
        raise TranslationError(
            f"字幕语言（{source}）与目标译文语言相同，无需翻译；请选择其他目标语言")

    chain = providers or [PROVIDERS[n] for n in default_provider_names()]
    pending = [s for s in transcript.segments
               if force or not (s.translation or "").strip()]
    already = len(transcript.segments) - len(pending)
    if not pending:
        log("所有句子均已有译文，无需翻译（勾选重译可覆盖）。")
        return 0, already, []

    log(f"开始翻译：{source} → {target}，待译 {len(pending)} 句"
        f"（已有译文 {already} 句）。")
    done = 0
    failed: list[int] = []
    for i, seg in enumerate(pending, 1):
        try:
            seg.translation = translate_text(seg.text, source, target, chain)
            done += 1
            log(f"  [{i}/{len(pending)}] {seg.text[:40]}  →  {seg.translation[:40]}")
        except TranslationError as e:
            failed.append(seg.id)
            log(f"  [{i}/{len(pending)}] 失败（句 {seg.id + 1}）：{e}")
        if i < len(pending) and pause:
            time.sleep(pause)
    log(f"翻译结束：新译 {done} 句，跳过 {already} 句，失败 {len(failed)} 句。")
    return done, already, failed
