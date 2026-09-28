# -*- coding: utf-8 -*-
"""Command-line entry point.

    python -m mll_subtitles.cli media [-o out.json]            # transcribe
    python -m mll_subtitles.cli media -t zh-CN                 # transcribe + translate
    python -m mll_subtitles.cli transcript.mll.json -t zh-CN   # translate an existing JSON
"""
import argparse
import os
import sys

from .schema import Transcript, validate
from .transcriber import MODEL_SIZES, transcribe_file
from .translator import PROVIDERS, TranslationError, translate_transcript


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="MyLangLean 字幕工坊（命令行）")
    parser.add_argument("media", help="音频/视频文件路径，或已有的 .mll.json 字幕文件")
    parser.add_argument("-o", "--output", help="输出 JSON 路径（默认与输入同名）")
    parser.add_argument("-m", "--model", default="small", choices=MODEL_SIZES)
    parser.add_argument("-l", "--language", default=None,
                        help="语言代码，如 en/zh；省略则自动检测（仅转写时有效）")
    parser.add_argument("--compute-type", default="int8",
                        choices=("int8", "float32"),
                        help="计算精度：int8（默认，CPU 快）或 float32（更准更慢）")
    parser.add_argument("-t", "--translate-to", default=None,
                        help="识别（或读取）字幕后自动翻译成目标语言，如 zh-CN/en/ja")
    parser.add_argument("--retranslate", action="store_true",
                        help="连同已有译文一起重新翻译（默认跳过已有译文）")
    parser.add_argument("--provider", default=None,
                        help="翻译通道，逗号分隔，如 mymemory,google；"
                             "默认 mymemory,google（也可用环境变量 "
                             "MLL_TRANSLATE_PROVIDER 设置）")
    args = parser.parse_args(argv)

    is_json = args.media.lower().endswith(".json")
    out = args.output
    if not out:
        stem = os.path.splitext(args.media)[0]
        if args.translate_to and is_json:
            out = f"{stem}.{args.translate_to}.mll.json"
        else:
            out = stem + ".mll.json"

    if is_json:
        print(f"读取已有字幕：{args.media}")
        transcript = Transcript.load_json(args.media)
    else:
        transcript = transcribe_file(
            args.media, model_size=args.model, language=args.language,
            compute_type=args.compute_type)

    if args.translate_to:
        providers = None
        if args.provider:
            names = [n.strip() for n in args.provider.split(",") if n.strip()]
            unknown = [n for n in names if n not in PROVIDERS]
            if unknown:
                print(f"未知翻译通道：{', '.join(unknown)}；可选："
                      f"{', '.join(sorted(set(PROVIDERS)))}", file=sys.stderr)
                return 2
            providers = [PROVIDERS[n] for n in names]
        try:
            done, already, failed = translate_transcript(
                transcript, args.translate_to,
                force=args.retranslate, providers=providers, log=print)
        except TranslationError as e:
            print("翻译未能开始：" + str(e), file=sys.stderr)
            return 3

    errors = validate(transcript)
    if errors:
        print("校验未通过：", file=sys.stderr)
        for e in errors:
            print(" - " + e, file=sys.stderr)
        return 2
    transcript.save_json(out)
    print(f"已导出：{out}")
    if args.translate_to and failed:
        print(f"警告：{len(failed)} 句翻译失败，已保留成功部分；"
              "可重新运行本命令（默认跳过已有译文）继续补译。", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
