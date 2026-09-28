# -*- coding: utf-8 -*-
"""Headless smoke test for the tkinter Studio (AC-4 evidence).

Exercises the real GUI code paths without a human: load a recognised
transcript, fix a word, nudge timings, add a translation, split/merge a
sentence, run the one-click machine-translation worker with an injected
provider, then run the same validate + export pipeline as 导出字幕.

Run with PYTHONPATH pointing at tools/subtitle-studio:
    python tools/subtitle-studio/tests/gui_smoke.py <in.json> <out.json>
"""
import sys
import time

from mll_subtitles import studio, translator
from mll_subtitles.schema import Transcript, validate


def _pump_until_idle(app, seconds=10):
    deadline = time.time() + seconds
    while app._busy and time.time() < deadline:
        app.update()
        time.sleep(0.02)
    app.update()
    assert not app._busy, "background worker did not finish in time"


def _install_fake_translator(marker):
    """Redirect the studio worker's translate_transcript at the real
    implementation but with a keyless in-memory provider (no network)."""
    real = translator.translate_transcript

    def fake_provider(text, src, tgt):
        return marker + text

    def patched(t, target_lang, **kwargs):
        return real(t, target_lang, providers=[fake_provider], pause=0,
                    force=kwargs.get("force", False),
                    log=kwargs.get("log", print))

    studio.translate_transcript = patched


def main(in_path: str, out_path: str) -> int:
    app = studio.Studio()
    app.update()

    # Load via the same entry point as "打开字幕(JSON)".
    app.transcript = Transcript.load_json(in_path)
    app._refresh_segments()
    n0 = len(app.transcript.segments)

    # Select segment 0 through the real tree handler.
    app.seg_tree.selection_set("0")
    app.update()
    assert app.current_seg == 0

    # Human correction 1: fix a word (strip the trailing period into a later
    # word style edit) and nudge its start time +0.05s via the real button fn.
    row = app._row_vars[0]
    row["w"].set("Real!")
    studio.Studio._nudge(row["s"], 0.05)

    # Human correction 2: add a Chinese translation.
    app.translation_var.set("真实的声音让语言鲜活起来。")
    app._save_translation()
    app._commit_current_segment()

    seg0 = app.transcript.segments[0]
    assert seg0.words[0].w == "Real!"
    assert seg0.translation == "真实的声音让语言鲜活起来。"

    # Add a word: it must survive the tree refresh (regression for stale
    # rows being committed back and wiping the new word).
    n_words = len(seg0.words)
    app._add_word()
    app.update()
    assert len(app.transcript.segments[0].words) == n_words + 1
    assert app.transcript.segments[0].words[-1].w == "新词"

    # Delete that trailing word: removal must persist too.
    app._delete_word(n_words)
    app.update()
    assert len(app.transcript.segments[0].words) == n_words

    # Split at the 3rd word: no duplicated words, monotonic global order,
    # and the result must validate BEFORE merging back (regression for the
    # stale-commit split that produced overlapping duplicate sentences).
    app._split_at(2)
    app.update()
    assert len(app.transcript.segments) == n0 + 1
    flat = [w.w for s in app.transcript.segments for w in s.words]
    assert len(flat) == sum(len(s.words) for s in
                            Transcript.load_json(in_path).segments)
    app.transcript.recompute_bounds()
    split_errors = validate(app.transcript)
    assert not split_errors, "split produced invalid transcript: %s" % split_errors

    app._merge_next()
    app.update()
    assert len(app.transcript.segments) == n0

    # Same export pipeline as Studio.export (minus the save dialog).
    app._commit_current_segment()
    app.transcript.recompute_bounds()
    errors = validate(app.transcript)
    if errors:
        print("VALIDATE_FAILED")
        for e in errors:
            print(" -", e)
        app.destroy()
        return 1

    app.transcript.save_json(out_path)

    # Round-trip: reload and prove the human edits persisted.
    check = Transcript.load_json(out_path)
    assert check.segments[0].words[0].w == "Real!"
    assert check.segments[0].translation == "真实的声音让语言鲜活起来。"
    assert len(check.segments) == n0

    # --- one-click translation regression (fake provider, no network) -----
    _install_fake_translator("[V1]")
    app.target_var.set("zh-CN")
    # Segment 0 carries the manual translation above; it must be preserved.
    app.start_translate()
    _pump_until_idle(app)
    assert "翻译完成" in app.status_var.get()
    assert app.transcript.segments[0].translation == "真实的声音让语言鲜活起来。"
    for i, s in enumerate(app.transcript.segments):
        if i == 0:
            continue
        assert s.translation and s.translation.startswith("[V1]"), \
            "segment %d was not translated: %r" % (i, s.translation)
    # The tree's 译文 column now marks every row and the editor reloaded.
    for i in range(n0):
        assert app.seg_tree.item(str(i), "values")[3] == "✓"
    assert app.translation_var.get()  # current segment editor refreshed

    # Only missing sentences are translated: wipe one and re-run with V2.
    app.transcript.segments[2].translation = None
    _install_fake_translator("[V2]")
    app.start_translate()
    _pump_until_idle(app)
    assert app.transcript.segments[2].translation.startswith("[V2]")
    assert app.transcript.segments[1].translation.startswith("[V1]")
    assert app.transcript.segments[0].translation == "真实的声音让语言鲜活起来。"

    # 全部重译 (force=True) overwrites machine output AND manual corrections.
    app.start_translate(force=True)
    _pump_until_idle(app)
    assert all(s.translation.startswith("[V2]")
               for s in app.transcript.segments)

    app.update()
    app.destroy()
    print("GUI_SMOKE_OK segments=%d words=%d -> %s"
          % (len(check.segments),
             sum(len(s.words) for s in check.segments), out_path))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: python gui_smoke.py <in.json> <out.json>")
        raise SystemExit(2)
    raise SystemExit(main(sys.argv[1], sys.argv[2]))
