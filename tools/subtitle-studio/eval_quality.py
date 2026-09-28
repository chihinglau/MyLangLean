# -*- coding: utf-8 -*-
"""
Quality gate for AC-3: compare a Studio transcript against a ground truth
whose words and word boundaries are known (the edge-tts aligned
app/assets/data/sample_transcript.json is such a ground truth).

Outputs:
  - word error rate (WER) on normalized tokens
  - per-word boundary error distribution (start times, aligned greedily)
  - pass/fail against the spec rubric (WER <= 10%, >=90% of matched words
    within 0.5s  -> score 5)
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_words(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    words, starts = [], []
    for seg in data["segments"]:
        for w in seg["words"]:
            words.append(w["w"])
            starts.append(float(w["s"]))
    return data.get("language", "en"), words, starts, float(data["duration"])


def norm(t):
    return "".join(c for c in t.lower() if c.isalnum() or c == "'")


def levenshtein(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1,
                           prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def main(truth, hyp, out):
    lang, tw, ts, tdur = load_words(truth)
    _, hw, hs, _ = load_words(hyp)
    tn = [norm(w) for w in tw if norm(w)]
    hn = [norm(w) for w in hw if norm(w)]

    wer = levenshtein(tn, hn) / max(1, len(tn))

    # Greedy ordered alignment of identical normalized tokens.
    i = j = 0
    deltas = []
    while i < len(tn) and j < len(hn):
        if tn[i] == hn[j]:
            deltas.append(abs(hs[j] - ts[i]))
            i += 1
            j += 1
        else:
            j += 1
    matched = len(deltas)
    within_05 = sum(1 for d in deltas if d <= 0.5)
    mean = sum(deltas) / matched if matched else float("inf")
    p90 = sorted(deltas)[int(0.9 * (matched - 1))] if matched else float("inf")

    score = 1
    if wer <= 0.10 and matched and within_05 / matched >= 0.9:
        score = 5
    elif wer <= 0.20 and matched and within_05 / matched >= 0.6:
        score = 3

    lines = [
        f"language={lang} truth_duration={tdur:.2f}s",
        f"truth_words={len(tn)} hyp_words={len(hn)} aligned={matched}",
        f"WER={wer*100:.2f}%",
        f"boundary start error: mean={mean:.3f}s p90={p90:.3f}s "
        f"within_0.5s={within_05}/{matched} "
        f"({within_05/max(1,matched)*100:.1f}%)",
        f"rubric_score={score}/5 (threshold >=4)",
        "PASS" if score >= 4 else "FAIL",
    ]
    report = "\n".join(lines)
    Path(out).write_text(report + "\n", encoding="utf-8")
    print(report)
    return 0 if score >= 4 else 1


if __name__ == "__main__":
    truth = sys.argv[1] if len(sys.argv) > 1 else \
        str(ROOT / "app/assets/data/sample_transcript.json")
    hyp = sys.argv[2] if len(sys.argv) > 2 else \
        str(ROOT / ".tools/studio-out/sample.mll.json")
    out = sys.argv[3] if len(sys.argv) > 3 else \
        str(ROOT / ".tools/studio-out/quality_report.txt")
    raise SystemExit(main(truth, hyp, out))
