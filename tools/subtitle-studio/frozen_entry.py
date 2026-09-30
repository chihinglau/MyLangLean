# -*- coding: utf-8 -*-
"""PyInstaller entry point for the Subtitle Studio exe.

Normal launch: show the tkinter GUI.
``SubtitleStudio.exe --selfcheck``: import every bundled native dependency
(no window is created), write the result next to the exe, and exit. This lets
an automated build verify the frozen package without a human.
"""
from __future__ import annotations

import os
import sys
import traceback


def _selfcheck() -> int:
    lines = ["MyLangLean Subtitle Studio self-check"]
    ok = True
    try:
        import platform

        lines.append(f"python: {platform.python_version()}")
        lines.append(f"frozen: {bool(getattr(sys, 'frozen', False))}")
        lines.append(f"exe: {sys.executable}")

        # Importing the transcriber FIRST pins HF_HOME / HF_XET_CACHE before
        # huggingface_hub pulls in the native hf_xet extension.
        from mll_subtitles.transcriber import _default_hf_cache
        from mll_subtitles.translator import normalize_lang

        assert normalize_lang("zh") == "zh-CN"
        lines.append(f"HF_HOME: {os.environ.get('HF_HOME')}")
        lines.append(f"default cache (no env): {_default_hf_cache()}")
        lines.append(f"hf-xet cache: {os.environ.get('HF_XET_CACHE')}")

        import tkinter  # GUI toolkit

        lines.append(f"tkinter: {tkinter.TkVersion}")

        import av  # PyAV native libs (ffmpeg)

        lines.append(f"av: {av.__version__}")

        import ctranslate2  # native inference runtime

        lines.append(f"ctranslate2: {ctranslate2.__version__}")

        import faster_whisper  # transcriber

        lines.append(f"faster_whisper: {faster_whisper.__version__}")

        # Our own package, including the translator module and full GUI.
        from mll_subtitles import studio  # noqa: F401

        lines.append("RESULT: OK")
    except Exception:  # report any missing/hook-broken native dependency
        ok = False
        lines.append("RESULT: FAIL")
        lines.append(traceback.format_exc())

    out_dir = (os.path.dirname(os.path.abspath(sys.executable))
               if getattr(sys, "frozen", False) else os.getcwd())
    log_path = os.path.join(out_dir, "studio-selfcheck.log")
    with open(log_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return 0 if ok else 1


def _opt(name: str, default=None):
    """Read ``--name value`` / ``--name=value`` from argv."""
    for i, arg in enumerate(sys.argv):
        if arg == name and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if arg.startswith(name + "="):
            return arg.split("=", 1)[1]
    return default


def _headless_transcribe() -> int:
    """Hidden batch mode: ``--transcribe media --out file [--model s --lang en]``.

    The exe is built as a windowed app, so stdout may be None; mirror every
    log line into ``<out>.log`` instead.
    """
    media = _opt("--transcribe")
    out = _opt("--out")
    model = _opt("--model", "small")
    lang = _opt("--lang") or None
    if not media or not out:
        sys.stderr.write("--transcribe and --out are required\n")
        return 2

    log_f = open(out + ".log", "w", encoding="utf-8")

    def log(msg: str) -> None:
        log_f.write(str(msg) + "\n")
        log_f.flush()
        try:
            print(msg, flush=True)
        except Exception:
            pass

    try:
        from mll_subtitles.transcriber import transcribe_file
        from mll_subtitles.schema import validate

        t = transcribe_file(media, model_size=model, language=lang, log=log)
        errors = validate(t)
        t.save_json(out)
        log(f"saved: {out}")
        log(f"segments={len(t.segments)} duration={t.duration:.1f}s "
            f"validate={'OK' if not errors else errors}")
        return 0 if not errors else 4
    except Exception:
        log(traceback.format_exc())
        return 1
    finally:
        log_f.close()


def main() -> int:
    if "--selfcheck" in sys.argv:
        return _selfcheck()
    if "--transcribe" in sys.argv:
        return _headless_transcribe()
    from mll_subtitles.studio import main as gui_main

    gui_main()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
