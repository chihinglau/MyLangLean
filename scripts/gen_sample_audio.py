# -*- coding: utf-8 -*-
"""
Generate the bundled sample voice + word-aligned transcript for MyLangLean.

Reads  app/assets/data/sample_transcript.json  (text + translations only),
speaks every segment with a neural TTS voice (edge-tts, en-US-JennyNeural),
collects real WordBoundary timings, then writes:
  app/assets/audio/sample.mp3
  app/assets/data/sample_transcript.json   (same text/translation/p, real timings)

Re-run when the sample script changes:
    .tools\\venvs\\mll\\Scripts\\python.exe scripts\\gen_sample_audio.py
"""
import asyncio
import json
import re
import sys
from pathlib import Path

import edge_tts

VOICE = "en-US-JennyNeural"
ROOT = Path(__file__).resolve().parent.parent
TRANSCRIPT = ROOT / "app" / "assets" / "data" / "sample_transcript.json"
AUDIO = ROOT / "app" / "assets" / "audio" / "sample.mp3"

TICKS = 10_000_000.0  # 100-ns units per second


def norm(word: str) -> str:
    return re.sub(r"[^a-z0-9']", "", word.lower())


async def synthesize(text: str, out: Path):
    communicate = edge_tts.Communicate(text, VOICE, boundary="WordBoundary", rate="-5%")
    boundaries = []
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wb") as f:
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                f.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                boundaries.append(chunk)
    return boundaries


def align(data: dict, boundaries: list) -> dict:
    flat_words = []
    for seg in data["segments"]:
        for w in seg["words"]:
            flat_words.append(w)

    spoken = [(norm(b["text"]), b["offset"] / TICKS, b["duration"] / TICKS)
              for b in boundaries if norm(b["text"])]
    expected = [norm(w["w"]) for w in flat_words]
    got = [s[0] for s in spoken]

    if expected != got:
        # Tolerate occasional tokenizer drift via ordered greedy alignment.
        print(f"[warn] token stream differs (expected {len(expected)}, got {len(got)}); "
              "using greedy alignment", file=sys.stderr)
        pairs = []
        i = j = 0
        while i < len(expected) and j < len(got):
            if expected[i] == got[j]:
                pairs.append((i, j)); i += 1; j += 1
            else:
                j += 1
        aligned = {i: spoken[j] for i, j in pairs}
    else:
        aligned = {i: spoken[i] for i in range(len(flat_words))}

    total = 0.0
    word_index = 0
    for seg in data["segments"]:
        seg_start = None
        seg_end = None
        for w in seg["words"]:
            idx = word_index
            word_index += 1
            if idx not in aligned:
                continue
            _, start, dur = aligned[idx]
            end = round(start + dur, 3)
            start = round(start, 3)
            w["s"] = start
            w["e"] = end
            seg_start = start if seg_start is None else min(seg_start, start)
            seg_end = end if seg_end is None else max(seg_end, end)
            total = max(total, end)
        if seg_start is not None:
            seg["start"] = seg_start
            seg["end"] = seg_end

    data["duration"] = round(total + 0.4, 2)  # small tail padding
    return data


async def main():
    data = json.loads(TRANSCRIPT.read_text(encoding="utf-8"))
    # Join segments on spaces; punctuation inside the script drives TTS pauses.
    text = " ".join(seg["text"].strip() for seg in data["segments"])
    print(f"speaking {len(data['segments'])} segments, {len(text)} chars ...")
    boundaries = await synthesize(text, AUDIO)
    print(f"audio -> {AUDIO} ({AUDIO.stat().st_size} bytes, {len(boundaries)} words)")
    data = align(data, boundaries)
    TRANSCRIPT.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"transcript -> {TRANSCRIPT}  duration={data['duration']}s")


if __name__ == "__main__":
    asyncio.run(main())
