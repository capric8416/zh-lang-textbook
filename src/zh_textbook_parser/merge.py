"""把逐页抽出的课文合并成完整的课文单元。

一篇课文常常跨好几页：带标题的那页开篇，后面没有标题的页是续页。合并时
要处理三件事：跨页断掉的句子、跨页延续的段落、分散在各页的注释。
"""

from __future__ import annotations

from .semantics import CLOSING, SPLIT_PUNCT

MERGE_KEYS = ("课号", "栏目", "课题", "标题", "标题注释号", "作者", "年代", "国别", "译者", "出处", "作者出处")
# 续页上才补得到的字段。课号/课题只认开篇那一页，续页上的是逐页继承的产物，
# 再填回来会把语文园地、识字表这类栏目也挂上上一课的课号。
FILL_KEYS = ("标题注释号", "作者", "年代", "国别", "译者", "出处", "作者出处", "整理者")


def _is_open(unit: dict) -> bool:
    """这句在本页结尾处还没写完。"""
    return bool(unit.get("跨页续句"))


def _place(unit: dict, page: dict) -> list[dict]:
    return [{"页码": page["页码"], "pdf页序": page["pdf页序"], "bbox": unit["bbox"]}]


def _new_lesson(page: dict) -> dict:
    lesson = page["课文"]
    out = {"单元": page.get("单元")}
    out.update({k: lesson.get(k) for k in MERGE_KEYS})
    out.update({"页码": [], "pdf页序": [], "注释": [], "正文": []})
    return out


def _append_notes(out: dict, page: dict) -> None:
    seen = {n["文本"] for n in out["注释"]}
    for note in page["课文"]["注释"]:
        if note["文本"] in seen:
            continue
        seen.add(note["文本"])
        out["注释"].append(
            {"文本": note["文本"], "页码": page["页码"], "bbox": note["bbox"]}
        )


def _fill_blank_fields(out: dict, page: dict) -> None:
    """续页上才出现的信息（比如脚注里的作者）补进课文单元。"""
    for key in FILL_KEYS:
        if out.get(key) is None and page["课文"].get(key) is not None:
            out[key] = page["课文"][key]


def _append_content(out: dict, page: dict) -> None:
    units = page["课文"]["正文"]
    if not units:
        return
    tail = out["正文"][-1] if out["正文"] else None

    if tail is None:
        offset, start = 0, 0
    elif _is_open(tail):
        # 上一页最后一句没写完，和本页第一句拼起来，段落也跟着上一句
        head = units[0]
        head_offset = len(tail["文本"])
        tail["文本"] += head["文本"]
        tail["字数"] = len(tail["文本"])
        tail["注音"] += [
            {**item, "序": item["序"] + head_offset}
            if "序" in item
            else dict(item)
            for item in head["注音"]
        ]
        tail["位置"] += _place(head, page)
        if tail["文本"][-1] in SPLIT_PUNCT + CLOSING + "、：":
            tail.pop("跨页续句", None)
        offset, start = tail["段落"] - 1, 1
    else:
        # 本页首行缩进说明另起一段，否则接着上一段往下排
        offset = tail["段落"] if page["课文"].get("首行缩进") else tail["段落"] - 1
        start = 0

    for unit in units[start:]:
        unit = dict(unit)
        unit["段落"] += offset
        unit["位置"] = _place(unit, page)
        unit.pop("bbox", None)
        out["正文"].append(unit)


def merge_lessons(pages: list[dict]) -> list[dict]:
    """按阅读顺序把各页的课文合并成课文单元列表。"""
    lessons: list[dict] = []
    current: dict | None = None
    for page in pages:
        lesson = page.get("课文")
        if not lesson:
            continue
        if lesson["标题"] or current is None:  # 有标题 = 新的一篇
            current = _new_lesson(page)
            lessons.append(current)
        else:
            _fill_blank_fields(current, page)
        current["页码"].append(page["页码"])
        current["pdf页序"].append(page["pdf页序"])
        _append_notes(current, page)
        _append_content(current, page)

    for lesson in lessons:
        for no, unit in enumerate(lesson["正文"], 1):
            unit["序号"] = no
        lesson["段落数"] = max((u["段落"] for u in lesson["正文"]), default=0)
        lesson["句数"] = len(lesson["正文"])
        lesson["全文"] = "".join(u["文本"] for u in lesson["正文"])
    return lessons
