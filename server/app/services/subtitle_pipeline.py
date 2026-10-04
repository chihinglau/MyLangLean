"""双语字幕流水线（爬虫自动产出 / 按需转录共用的同一组装逻辑）。

编排两个已有服务，零新依赖：
    asr.transcribe(source, language)   -> 逐词源语言识别结果
    translate.translate(texts, s, t)   -> 每个句子的目标语言译文

输出 TranscriptOut（其 JSON 与各端 Transcript.fromJson 的冻结帧格式一致，
格式改动只能 bump version，禁止在此调整字段）。

"自动调用字幕工坊"在服务端即对应本流水线：生产环境把 ASR 后端切到
faster_whisper（MLL_ASR_BACKEND=faster_whisper）后，与桌面字幕工坊
使用完全相同的识别引擎与逐词时间戳，再叠加中文翻译产出双语字幕。
"""
from __future__ import annotations

import json

from ..models import SegmentOut, TranscriptOut, WordOut
from . import asr as asr_service
from .translate import translate


def build_transcript(source: str, language: str = "en",
                     target_lang: str | None = None) -> TranscriptOut:
    """识别 [source] 并按需翻译，组装成逐词（双语）字幕。

    target_lang 为 None / 空串时只产出源语言字幕。ASR 异常直接向上抛出，
    由调用方决定单集降级策略；翻译环节异常 / 单句翻译失败则该句只保留
    源语言文本（translation 留空），绝不因翻译问题让整集字幕缺失。
    """
    result = asr_service.transcribe(source, language)

    translations: dict[int, str] = {}
    if target_lang:
        texts = [s.text for s in result.segments]
        try:
            translated = translate(texts, result.language, target_lang)
        except Exception:  # noqa: BLE001 - 翻译整体不可用：降级为源语言
            translated = []
        for seg_id, text in zip(
            [s.id for s in result.segments], translated
        ):
            text = (text or "").strip()
            if text:
                translations[seg_id] = text

    return TranscriptOut(
        language=result.language,
        duration=result.duration,
        segments=[
            SegmentOut(
                id=s.id,
                start=s.start,
                end=s.end,
                text=s.text,
                translation=translations.get(s.id),
                words=[
                    WordOut(w=w.w, s=w.s, e=w.e, p=w.p) for w in s.words
                ],
            )
            for s in result.segments
        ],
    )


def build_transcript_json(source: str, language: str = "en",
                          target_lang: str | None = None) -> str:
    """同 build_transcript，直接返回可落库/随候选快照存储的 JSON 串。"""
    return json.dumps(
        build_transcript(source, language, target_lang).model_dump(),
        ensure_ascii=False)
