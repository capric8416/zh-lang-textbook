"""页面级组装：把一页解析成语义单元 JSON。"""

from __future__ import annotations

import re
from pathlib import Path

import fitz

from .blocks import page_images, page_lines, page_rules, round_box
from .appendix import appendix_title, merge_appendices, parse_appendix
from .garden import (
    is_garden_page,
    merge_gardens,
    parse_garden,
    selection_label_y,
)
from .merge import merge_lessons
from .regions import footer_json, header_json, split_regions
from .semantics import (
    dominant_size,
    lesson_dominant,
    extract_after_class,
    extract_lesson,
    split_after_class,
)


def parse_page(
    doc: fitz.Document, index: int, full: bool = False, prefer: str | None = None
) -> dict:
    """index 为 0 基的 PDF 页序号。

    默认只输出课文单元；页眉 / 页脚 / 右边栏 / 课后仍会照常识别，只是用于把
    它们从课文区里剔除，不写进结果。full=True 时输出全部版面单元。
    """
    page = doc[index]
    width, height = page.rect.width, page.rect.height
    lines = page_lines(page)
    regions = split_regions(lines, width, height)

    footer = footer_json(regions.footer)
    page_no = footer["页码"] if footer else None

    # 封面、版权页、目录没有印刷页码，不做课文/课后抽取
    lesson = after = garden = appendix = None
    if page_no is not None:
        body = regions.body
        if appendix_title(body) or prefer == "附录":
            appendix = parse_appendix(body)
            body = []
        elif prefer == "园地" or is_garden_page(body):
            # 一页里可能上半是园地栏目、下半是「我爱阅读」整篇选文
            cut = selection_label_y(body)
            upper = [ln for ln in body if cut is None or ln.y0 < cut - 1]
            body = [ln for ln in body if cut is not None and ln.y0 >= cut - 1]
            garden = parse_garden(upper, page_rules(page)) if upper else None
        if body:
            lesson_lines, after_lines = split_after_class(body)
            lesson, rest = extract_lesson(
                lesson_lines, lesson_dominant(lesson_lines, body)
            )
            after = extract_after_class(
                sorted(after_lines + rest, key=lambda ln: (round(ln.y0), ln.x0)),
                page_rules(page),
            )

    if appendix:
        kind = "附录页"
    elif garden and lesson:
        kind = "语文园地页+选文"
    elif garden:
        kind = "语文园地页"
    elif lesson and after:
        kind = "课文页+课后"
    elif lesson:
        kind = "课文页"
    elif after:
        kind = "课后页"
    else:
        kind = "前置页"  # 封面、版权页、目录等

    head = header_json(regions.header, width)
    result = {
        "pdf页序": index + 1,
        "页码": int(page_no) if page_no and page_no.isdigit() else None,
        "单元": unit_label(head["文本"] if head else None),
        "课文": lesson,
        "园地": garden,
        "附录": appendix,
    }
    if not full:
        return result

    result.update(
        {
            "页面类型": kind,
            "页面尺寸": {"宽": round(width, 1), "高": round(height, 1)},
            "页眉": head,
            "页脚": footer,
            "右边栏": [
                {"文本": ln.text(), "bbox": round_box(ln.bbox)} for ln in regions.sidebar
            ],
            "课后": after,
            "插图数": len(page_images(page)),
        }
    )
    if kind == "前置页":
        result["原始文本行"] = [
            {"文本": ln.text(), "字号": ln.size, "bbox": round_box(ln.bbox)}
            for ln in regions.body
        ]
    return result


UNIT_RE = re.compile(r"^第([一二三四五六七八九十]+)单元[·・]?(\S*)")
CN_NUM = "一二三四五六七八九十"


def unit_label(text: str | None) -> dict | None:
    """页眉角标「第一单元·阅读」→ {"单元": 1, "类型": "阅读"}。"""
    m = UNIT_RE.match(text or "")
    if not m:
        return None
    return {"单元": CN_NUM.index(m.group(1)[0]) + 1, "类型": m.group(2) or None}


LOOKBACK = 20  # 往前回溯多少页去找当前课的课号/课题


def _inherit(lesson: dict, state: dict) -> None:
    """课号为空的页沿用上一课的课号与课题。

    两种情况可以继承：没有标题的续页；以及「古诗二首」这种一课多篇的后续
    篇目 —— 后者以上一课带课题为判据，免得把语文园地这类栏目页也算进去。
    """
    if lesson["课号"] is not None:
        state["课号"] = lesson["课号"]
        state["课题"] = lesson["课题"]
        return
    if lesson["标题"] and state.get("课题") is None:
        return  # 新起的栏目页，不属于上一课
    lesson["课号"] = state.get("课号")
    if lesson["课题"] is None:
        lesson["课题"] = state.get("课题")


def _seed_context(doc: fitz.Document, first: int) -> dict:
    """解析区间不是从头开始时，往前回溯出当前课的课号/课题。"""
    for i in range(first - 1, max(-1, first - 1 - LOOKBACK), -1):
        lesson = parse_page(doc, i)["课文"]
        if lesson and lesson["课号"] is not None:
            return {"课号": lesson["课号"], "课题": lesson["课题"]}
    return {}


def parse_pages(pdf_path: str, indexes: list[int], full: bool = False) -> dict:
    doc = fitz.open(pdf_path)
    try:
        total = len(doc)
        wanted = [i for i in indexes if 0 <= i < total]
        state = _seed_context(doc, min(wanted)) if wanted and min(wanted) > 0 else {}
        pages = []
        prev = None  # 上一页最后一块是什么，决定没有标题的续页归给谁
        unit = None  # 单元角标只在每单元第一页出现，往后顺延
        for i in wanted:
            page = parse_page(doc, i, full)
            plain = page["课文"] and not page["课文"]["标题"] and not page["课文"]["课号"]
            if prev in ("园地", "附录") and not page["园地"] and not page["附录"]:
                if plain or not page["课文"]:
                    page = parse_page(doc, i, full, prefer=prev)
            if page["附录"]:
                prev = "附录"
            elif page["课文"]:
                _inherit(page["课文"], state)
                prev = "课文"
            elif page["园地"]:
                prev = "园地"
            unit = page["单元"] or unit
            page["单元"] = unit
            pages.append(page)
    finally:
        doc.close()
    result = {"文件": Path(pdf_path).name, "总页数": total}
    if full:
        result["页"] = pages
    else:
        result["课文"] = merge_lessons(pages)
        result["语文园地"] = merge_gardens(pages)
        result["附录"] = merge_appendices(pages)
    return result
