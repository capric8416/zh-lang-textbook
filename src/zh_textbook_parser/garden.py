"""语文园地页的抽取。

园地页和课文页的排版完全不同：一页里有若干个黑体小标题（识字加油站、字词
句运用、书写提示、日积月累……），每块下面是导览图上的词条、例句、田字格、
古诗等等，很多词条按图上的位置摆放，同一 y 上并排好几个，不能按句子拼。
所以这里不做断句，只按「栏目 → 条目」保留，条目按版面空隙切开。
"""

from __future__ import annotations

import re

from .blocks import Line, normalize
from .semantics import (
    SECTION_FONT,
    is_wrapped,
    line_right_edge,
    merge_item,
    _grid_chars,
    _is_cjk,
    dominant_size,
    extract_lesson,
    recognize_strip_groups,
)

# 必须整行就是标题：识字表里「语文园地一 亭 咨 询 …」这种行不算
TITLE_RE = re.compile(r"^语文园地[一二三四五六七八九十]+$")
# 黑体小标题里，「我爱阅读」是整篇选文，按课文处理，不算园地栏目
SELECTION_LABELS = ("我爱阅读",)
CONTENT_ONLY_SECTIONS = ("日积月累",)


def _dedupe(text: str) -> str:
    """有的标签是叠印两遍的（识字加油站识字加油站）。"""
    half = len(text) // 2
    return text[:half] if half and text[:half] == text[half:] else text


def label_of(line: Line) -> tuple[str | None, Line | None]:
    """行首的黑体小标题，返回 (栏目名, 去掉标题后剩下的行)。

    栏目名后面常常紧跟着同一行的正文（识字加油站 + 右边的例句），
    所以要在 span 级别切，不能整行判断。
    """
    lead: list = []
    for span in line.spans:
        if span.font.startswith(SECTION_FONT) and span.size >= 15:
            lead.append(span)
        else:
            break
    if not lead:
        return None, line
    name = _dedupe(normalize("".join(s.text for s in lead)))
    if not name or len(name) > 8:
        return None, line
    tail = line.spans[len(lead) :]
    if not tail:
        return name, None
    left = tail[0].bbox[0]
    rest = Line(tail, [c for c in line.chars if c.bbox[0] >= left - 0.5])
    return name, rest


def is_section_label(line: Line) -> bool:
    name, _ = label_of(line)
    return bool(name) and name not in SELECTION_LABELS


def selection_label_y(body: list[Line]) -> float | None:
    """「我爱阅读」标签所在的 y —— 它下面是整篇选文，不属于园地栏目。"""
    for ln in body:
        name, _ = label_of(ln)
        if name in SELECTION_LABELS:
            return ln.y0
    return None


def is_garden_page(body: list[Line]) -> bool:
    """整页是不是园地页：有「语文园地X」大标题，或者有黑体栏目标题。"""
    return any(TITLE_RE.match(ln.text()) for ln in body) or any(
        is_section_label(ln) for ln in body
    )


def _items(lines: list[Line], rules, written: set[str]) -> list[dict]:
    """行 → 条目：按版面空隙切段，整行排满又没写完的并入下一行。

    田字格里的字不参与拼接（它们和说明文字常常排在同一行）。
    """
    right = line_right_edge(lines)
    out: list[dict] = []
    prev_line: Line | None = None
    for ln in lines:
        segs = ln.segments(rules)
        if not segs:
            continue
        if (
            out
            and prev_line is not None
            and not _only_grid(segs[0]["文本"], written)
            and is_wrapped(prev_line, out[-1]["文本"], ln, right)
        ):
            merge_item(out[-1], segs[0])
            segs = segs[1:]
        out.extend(segs)
        prev_line = ln
    return [item for item in out if not _only_grid(item["文本"], written)]


def _only_grid(text: str, written: set[str]) -> bool:
    """这段是不是只有田字格里的字（黑字 + 描红字）。"""
    plain = text.replace(" ", "")
    return bool(plain) and len(plain) <= 4 and all(c in written for c in plain)


def _section(name: str | None, lines: list[Line], rules) -> dict:
    """一个栏目块：生字条、田字格、其余条目，外加可能的整首选文。"""
    used: set[int] = set()
    recognize: list[dict] = []
    strip_indexes = {
        index for group in recognize_strip_groups(lines) for index in group
    }
    for i, ln in enumerate(lines):
        if name not in CONTENT_ONLY_SECTIONS and i in strip_indexes:
            recognize.extend(
                {"字": c.char, "拼音": c.pinyin}
                for c in ln.visible_chars()
                if _is_cjk(c.char)
            )
            used.add(id(ln))

    rest = [ln for ln in lines if id(ln) not in used]
    grid = _grid_chars(rest)
    write: list[str] = []
    if grid:
        cells: list[str] = []
        for c in sorted(grid, key=lambda c: (round(c.bbox[1]), c.cx)):
            if not cells or cells[-1] != c.char:
                cells.append(c.char)
        write = cells

    # 日积月累里的古诗有标题和作者行，按课文结构单独抽出来，
    # 被它用掉的行就不再重复进条目
    selection, leftover = extract_lesson(rest, dominant_size(rest))
    picked = bool(selection and selection["作者"] and selection["正文"])

    # 田字格的字自成一段，剔掉它们，同一行上的说明文字要留着
    written = set(write)
    items = _items(leftover if picked else rest, rules, written)
    if name in CONTENT_ONLY_SECTIONS:
        # 日积月累常为逐字疏排；分栏已由 _items 切成独立条目，条目内部的
        # 空格只是 PDF 字距，不是换行或词语间隔。
        for item in items:
            item["文本"] = item["文本"].replace(" ", "")
    section = {
        "名称": name,
        "生字": recognize,
        "会写": write,
        "条目": items,
    }
    if picked:
        if selection["标题"] is None and selection["正文"]:
            # 「悯 农 （其 一）」这种标题和正文一样大，还被字距切成几段，
            # 就把作者行以上、正文以上的条目拼成标题
            top = selection["正文"][0]["bbox"][1]
            head = [it for it in items if it["bbox"][3] <= top]
            if head:
                selection["标题"] = "".join(it["文本"] for it in head).replace(" ", "")
                items = [it for it in items if it not in head]
                section["条目"] = items
        section["选文"] = {k: selection[k] for k in ("标题", "作者", "年代", "正文")}
    return section


def parse_garden(body: list[Line], rules, continuation: bool = False) -> dict | None:
    """把一页园地拆成 {标题, 栏目[]}。"""
    if not body:
        return None
    title = None
    lines = list(body)
    for ln in lines:
        if TITLE_RE.match(ln.text()):
            title = ln.text()
            lines.remove(ln)
            break

    marks = [i for i, ln in enumerate(lines) if is_section_label(ln)]
    if not marks and title is None:
        if continuation:
            return {"标题": None, "栏目": [_section(None, lines, rules)]}
        return None

    sections: list[dict] = []
    lead = lines[: marks[0]] if marks else lines
    if lead:
        # 页首没有标题的部分，是上一页那个栏目的续排
        sections.append(_section(None, lead, rules))
    for n, start in enumerate(marks):
        end = marks[n + 1] if n + 1 < len(marks) else len(lines)
        name, rest = label_of(lines[start])
        body = ([rest] if rest else []) + lines[start + 1 : end]
        sections.append(_section(name, body, rules))
    return {"标题": title, "栏目": sections}


def merge_gardens(pages: list[dict]) -> list[dict]:
    """把逐页的园地合并成整个「语文园地X」单元。"""
    units: list[dict] = []
    current: dict | None = None
    for page in pages:
        garden = page.get("园地")
        if not garden:
            continue
        if garden["标题"] or current is None:
            current = {
                "单元": page.get("单元"),
                "标题": garden["标题"],
                "页码": [],
                "pdf页序": [],
                "栏目": [],
            }
            units.append(current)
        current["页码"].append(page["页码"])
        current["pdf页序"].append(page["pdf页序"])
        for section in garden["栏目"]:
            section = dict(section)
            if section["名称"] is None and current["栏目"]:
                # 跨页续排：并回上一个栏目
                prev = current["栏目"][-1]
                continuation = [dict(item) for item in section["条目"]]
                if prev["名称"] == "和大人一起读":
                    for item in continuation:
                        item["文本"] = item["文本"].replace(" ", "")
                if prev.get("选文"):
                    # 选文正文由上一页的「选文」保存；续页必须排在它后面，
                    # 不能并入标题之前的普通条目。
                    prev.setdefault("续排", []).extend(continuation)
                else:
                    prev["条目"] += continuation
                prev["生字"] += section["生字"]
                prev["会写"] += section["会写"]
                continue
            section["页码"] = page["页码"]
            current["栏目"].append(section)
    return units
