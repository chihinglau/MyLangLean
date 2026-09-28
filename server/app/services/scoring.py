"""V1 heuristic shadowing score (server mirror of the on-device algorithm).

V2 will use forced alignment (wav2vec2 / whisper) for per-phoneme GOP once the
client uploads the actual recording waveform.
"""
from dataclasses import dataclass


@dataclass
class Score:
    overall: int
    rhythm: int
    fluency: int
    intonation: int
    suggestions: list[str]


def score(reference_ms: int, attempt_ms: int, pause_count: int) -> Score:
    ref = max(reference_ms, 500)
    att = max(attempt_ms, 500)
    ratio = att / ref

    rhythm = int(max(0, min(100, 100 - abs(ratio - 1.0) * 120)))
    fluency = max(40, min(100, 100 - pause_count * 12))
    intonation = 78
    overall = round(rhythm * 0.4 + fluency * 0.4 + intonation * 0.2)

    suggestions: list[str] = []
    if ratio > 1.25:
        suggestions.append("整体偏慢，试着跟上主播的节奏连读。")
    if ratio < 0.8:
        suggestions.append("语速过快，注意每个词的完整发音。")
    if pause_count >= 2:
        suggestions.append("中间停顿较多，先把这一句拆成两半练习。")
    if rhythm >= 85 and pause_count <= 1:
        suggestions.append("节奏很好！尝试不看字幕再跟读一遍。")
    if not suggestions:
        suggestions.append("继续保持，多练几遍形成肌肉记忆。")

    return Score(overall, rhythm, fluency, intonation, suggestions)
