"""命令行入口。

    uv run zh-textbook --pages 6-8            # 按 PDF 页序（1 基）
    uv run zh-textbook --printed 1-3          # 按课本印刷页码
    uv run zh-textbook --printed 1-3 -o a.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import fitz

from .extract import parse_pages
from .struct import build as build_struct
from .regions import page_number, split_regions
from .blocks import page_lines

DEFAULT_PDF = "zh-lang-grade2b-textbook.pdf"


def parse_spec(spec: str) -> list[int]:
    """'6-8,12' -> [5,6,7,11]（转成 0 基）"""
    out: list[int] = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a) - 1, int(b)))
        else:
            out.append(int(part) - 1)
    return out


def printed_to_index(pdf: str, wanted: set[int]) -> list[int]:
    """把印刷页码映射到 PDF 页序（读页脚页码）。"""
    doc = fitz.open(pdf)
    found: dict[int, int] = {}
    try:
        for i in range(len(doc)):
            page = doc[i]
            regions = split_regions(
                page_lines(page), page.rect.width, page.rect.height
            )
            for ln in regions.footer:
                no = page_number(ln.text())
                if no and int(no) in wanted and int(no) not in found:
                    found[int(no)] = i
            if len(found) == len(wanted):
                break
    finally:
        doc.close()
    return [found[k] for k in sorted(found)]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="zh-textbook", description="小学语文课本 PDF 语义单元抽取")
    ap.add_argument("--pdf", default=DEFAULT_PDF)
    ap.add_argument("--pages", help="PDF 页序，1 基，如 6-8")
    ap.add_argument("--printed", help="课本印刷页码，如 1-3")
    ap.add_argument("-o", "--out", help="输出 JSON 文件，默认打印到 stdout")
    ap.add_argument(
        "--full", action="store_true", help="按页输出全部版面单元（页眉/页脚/边栏/课后）"
    )
    ap.add_argument(
        "--struct", action="store_true", help="输出简化结构：目录 + 课文 + 园地 + 附录，逐字注音"
    )
    args = ap.parse_args(argv)

    if not Path(args.pdf).exists():
        print(f"找不到 PDF：{args.pdf}", file=sys.stderr)
        return 1

    if args.printed:
        indexes = printed_to_index(args.pdf, set(n + 1 for n in parse_spec(args.printed)))
    elif args.pages:
        indexes = parse_spec(args.pages)
    else:
        indexes = printed_to_index(args.pdf, {1, 2, 3})

    data = parse_pages(args.pdf, indexes, full=args.full)
    if args.struct:
        data = build_struct(data)
    text = json.dumps(data, ensure_ascii=False, indent=2)
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
        n = len(data.get("课文", data.get("页", [])))
        unit = "页" if args.full else "篇课文"
        print(f"已写入 {args.out}（{n} {unit}）", file=sys.stderr)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
