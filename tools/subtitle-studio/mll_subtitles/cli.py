# -*- coding: utf-8 -*-
"""Command-line entry point: python -m mll_subtitles.cli media [-o out.json]"""
import argparse
import os
import sys

from .schema import validate
from .transcriber import MODEL_SIZES, transcribe_file


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="MyLangLean 字幕工坊（命令行）")
    parser.add_argument("media", help="音频或视频文件路径")
    parser.add_argument("-o", "--output", help="输出 JSON 路径（默认与媒体同名）")
    parser.add_argument("-m", "--model", default="small", choices=MODEL_SIZES)
    parser.add_argument("-l", "--language", default=None,
                        help="语言代码，如 en/zh；省略则自动检测")
    parser.add_argument("--compute-type", default="int8",
                        choices=("int8", "float32"),
                        help="计算精度：int8（默认，CPU 快）或 float32（更准更慢）")
    args = parser.parse_args(argv)

    out = args.output
    if not out:
        stem = os.path.splitext(args.media)[0]
        out = stem + ".mll.json"

    transcript = transcribe_file(
        args.media, model_size=args.model, language=args.language,
        compute_type=args.compute_type)
    errors = validate(transcript)
    if errors:
        print("校验未通过：", file=sys.stderr)
        for e in errors:
            print(" - " + e, file=sys.stderr)
        return 2
    transcript.save_json(out)
    print(f"已导出：{out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
