"""书末附录：识字表 / 写字表 / 词语表。

三张表的版式一样：大标题，下面按「阅读 / 识字」分组，每组里一行一课
（行首是课号或「语文园地X」），排不下就折到下一行（下一行没有行首标签）。
差别只在每行的内容：

    识字表  1 咏 贺 妆 …   带注音的单字
    写字表  1 诗碧妆绿丝剪童归  单字，不带注音
    词语表  2 春天 寻找 眉毛 …  词语，空格分隔
"""

from __future__ import annotations

import re

from .blocks import Line, round_box

TITLE_RE = re.compile(r"^(识字表|写字表|词语表)$")
LABEL_RE = re.compile(r"^(\d{1,2}|语文园地[一二三四五六七八九十]+)")
NOTE_RE = re.compile(r"^[①-⑳]")
GROUP_FONT = "FZS3K"  # 「阅读」「识字」这种分组标签用的字体
TITLE_MIN_SIZE = 20


def _clean(text: str) -> str:
    return re.sub(r"[\s①-⑳]", "", text)


def appendix_title(body: list[Line]) -> str | None:
    """这一页是不是某张表的首页，是就返回表名。"""
    for ln in body:
        if ln.size >= TITLE_MIN_SIZE and TITLE_RE.match(_clean(ln.text())):
            return _clean(ln.text())
    return None


def _split_label(line: Line) -> tuple[str | None, list, str]:
    """切掉行首的课号 / 语文园地标签，返回 (标签, 余下的字, 余下的文本)。

    文本要保留词间空格 —— 词语表就靠它分词。
    """
    text = line.text()
    chars = [c for c in line.visible_chars() if c.char.strip()]
    m = LABEL_RE.match(text)
    if not m:
        return None, chars, text.strip()
    want = m.group(1)
    i = 0
    while i < len(chars) and want:
        if chars[i].char == want[0]:
            want = want[1:]
        i += 1
    return m.group(1), chars[i:], text[m.end() :].strip()


def _row(label: str | None, chars: list, text: str) -> dict:
    return {
        "标签": label,
        "字": [
            {"字": c.char, "拼音": c.pinyin}
            for c in chars
            if "一" <= c.char <= "鿿"
        ],
        "文本": text,
    }


def parse_appendix(body: list[Line]) -> dict | None:
    """把一页附录拆成 {名称, 分组[], 注释[]}。"""
    title = None
    groups: list[dict] = []
    notes: list[dict] = []
    for ln in body:
        text = ln.text()
        if ln.size >= TITLE_MIN_SIZE and TITLE_RE.match(_clean(text)):
            title = _clean(text)
            continue
        if NOTE_RE.match(text) and ln.size < 14:
            notes.append({"文本": text, "bbox": round_box(ln.bbox)})
            continue
        if any(f.startswith(GROUP_FONT) for f in ln.fonts) and len(_clean(text)) <= 6:
            groups.append({"名称": _clean(text), "行": []})
            continue
        label, chars, text = _split_label(ln)
        if not chars:
            continue
        if not groups:
            groups.append({"名称": None, "行": []})
        rows = groups[-1]["行"]
        if label is None and rows:  # 折行，接着上一行
            row = _row(None, chars, text)
            rows[-1]["字"] += row["字"]
            rows[-1]["文本"] += " " + row["文本"]
        else:
            rows.append(_row(label, chars, text))
    if not (title or groups):
        return None
    return {"名称": title, "分组": groups, "注释": notes}


def _content(name: str | None, row: dict) -> list:
    """按表的种类把一行整理成最终内容。"""
    if name == "识字表":
        return row["字"]
    if name == "词语表":
        return row["文本"].split()
    return [c["字"] for c in row["字"]]  # 写字表：单字


def merge_appendices(pages: list[dict]) -> list[dict]:
    """把逐页的附录合并成整张表。"""
    units: list[dict] = []
    current: dict | None = None
    for page in pages:
        part = page.get("附录")
        if not part:
            continue
        if part["名称"] or current is None:
            current = {"名称": part["名称"], "页码": [], "注释": [], "分组": []}
            units.append(current)
        current["页码"].append(page["页码"])
        current["注释"] += part["注释"]
        for group in part["分组"]:
            rows = group["行"]
            if group["名称"] is None and current["分组"]:
                prev = current["分组"][-1]["行"]
                if rows and rows[0]["标签"] is None and prev:  # 跨页折行
                    prev[-1]["字"] += rows[0]["字"]
                    prev[-1]["文本"] += " " + rows[0]["文本"]
                    rows = rows[1:]
                prev += rows
            else:
                current["分组"].append({"名称": group["名称"], "行": list(rows)})

    for unit in units:
        for group in unit["分组"]:
            group["行"] = [
                {"标签": r["标签"], "内容": _content(unit["名称"], r)}
                for r in group["行"]
                if r["字"]
            ]
        unit["条数"] = sum(len(g["行"]) for g in unit["分组"])
    return units
