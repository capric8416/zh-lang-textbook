#!/usr/bin/env python3
"""Generate a schema-v2 reviewed textbook from its ``reference`` sources.

The reviewed file keeps the hand-editable reference block as the source of
truth.  The parser JSON supplies catalog, lesson, garden, and appendix data;
the other reference paths are resolved as a guard against stale templates.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from zh_textbook_parser.struct import REVIEWED_PHRASE_FIX, annotate


CHINESE_NUMERALS = "零一二三四五六七八九十"
FOOTNOTE_MARKS = frozenset("①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳")
POEM_TITLES = {
    "金木水火土",
    "植物妈妈有办法",
    "场景歌",
    "树之歌",
    "拍手歌",
    "田家四季歌",
    "江南",
    "雪地里的小画家",
    "四季",
    "对韵歌",
    "日月明",
    "小书包",
    "升国旗",
    "小小的船",
    "影子",
    "两件宝",
    "比尾巴",
    "雨点儿",
    "春夏秋冬",
    "姓氏歌",
    "小青蛙",
    "热爱中国共产党",
    "静夜思",
    "夜色",
    "动物儿歌",
    "古对今",
    "操场上",
    "人之初",
    "雷锋叔叔，你在哪里",
    "神州谣",
    "传统节日",
    "彩色的梦",
}
GARDEN_POEMS = {
    "咏鹅": ("骆宾王", "唐"),
    "画": ("", ""),
    "悯农（其二）": ("李绅", "唐"),
    "古朗月行（节选）": ("李白", "唐"),
    "风": ("李峤", "唐"),
    "春晓": ("孟浩然", "唐"),
    "寻隐者不遇": ("贾岛", "唐"),
    "赠汪伦": ("李白", "唐"),
    "画鸡": ("唐寅", "明"),
    "梅花": ("王安石", "宋"),
    "数九歌": ("", ""),
    "小儿垂钓": ("胡令能", "唐"),
    "夜宿山寺": ("李白", "唐"),
    "赋得古原草送别（节选）": ("白居易", "唐"),
    "一株紫丁香": ("", ""),
    "二十四节气歌": ("", ""),
    "悯农（其一）": ("李绅", "唐"),
    "江上渔者": ("范仲淹", "宋"),
}
GARDEN_READINGS = {
    "妞妞赶牛": ("", "poem"),
    "快乐的节日": ("管桦", "poem"),
    "谁和谁好": ("张玉庭", "poem"),
    "胖乎乎的小手": ("望安", "prose"),
    "孙悟空打妖怪": ("樊家信", "poem"),
    "夏夜多美": ("彭万洲", "prose"),
    "狐狸和乌鸦": ("", "prose"),
    "小熊住山洞": ("胡木仁", "prose"),
}


@dataclass(frozen=True)
class SourceText:
    text: str
    syllables: tuple[str, ...]

    @classmethod
    def from_json(cls, text: str, pinyin: str) -> "SourceText":
        syllables = tuple(pinyin.split(" ")) if text else ()
        if len(text) != len(syllables):
            raise ValueError(
                f"正文与拼音没有逐字对齐: text={len(text)}, pinyin={len(syllables)}"
            )
        removed: set[int] = set()
        for index, char in enumerate(text):
            if char not in FOOTNOTE_MARKS:
                continue
            removed.add(index)
            before = index - 1
            while before >= 0 and text[before].isspace():
                removed.add(before)
                before -= 1
        if removed:
            text = "".join(
                char for index, char in enumerate(text) if index not in removed
            )
            syllables = tuple(
                value for index, value in enumerate(syllables) if index not in removed
            )
        return cls(text, syllables)

    def slice(self, start: int, end: int) -> tuple[str, str]:
        while start < end and self.text[start].isspace():
            start += 1
        while end > start and self.text[end - 1].isspace():
            end -= 1
        text = self.text[start:end]
        syllables = list(self.syllables[start:end])
        for phrase, values in REVIEWED_PHRASE_FIX.items():
            phrase_start = text.find(phrase)
            while phrase_start >= 0:
                for offset, value in enumerate(values):
                    syllables[phrase_start + offset] = value[0]
                phrase_start = text.find(phrase, phrase_start + 1)
        return text, " ".join(syllables)


def _resolve_reference(root: Path, output: Path, value: str) -> Path:
    direct = (output.parent / value).resolve()
    if direct.exists():
        return direct
    basename = Path(value).name
    candidates = sorted(root.glob(f"**/{basename}"))
    candidates = [candidate for candidate in candidates if candidate.resolve() != output.resolve()]
    if len(candidates) != 1:
        raise FileNotFoundError(
            f"无法唯一解析 reference 路径 {value!r}: {[str(path) for path in candidates]}"
        )
    return candidates[0].resolve()


def _pair(zh: str | None) -> dict[str, str]:
    if not zh:
        return {}
    return {"zh": zh, "pinyin": annotate(zh)}


def _unit_from_label(label: str) -> int:
    suffix = label.removeprefix("语文园地")
    if suffix.isdigit():
        return int(suffix)
    if suffix in CHINESE_NUMERALS:
        return CHINESE_NUMERALS.index(suffix)
    raise ValueError(f"无法识别单元标签: {label}")


def _ranges(source: SourceText, mode: str) -> list[tuple[int, int]]:
    text = source.text
    if not text:
        return []
    terminal = "，。！？；" if mode == "poem" else "。！？；"
    ranges: list[tuple[int, int]] = []
    start = 0
    index = 0
    while index < len(text):
        ch = text[index]
        split = ch in terminal
        if split:
            end = index if ch.isspace() else index + 1
            while end < len(text) and text[end] in "”’》」』】":
                end += 1
            if source.slice(start, end)[0]:
                ranges.append((start, end))
            start = max(end, index + 1)
            index = start
            continue
        if mode == "exercise" and ch in "◇◎" and source.slice(start, index)[0]:
            ranges.append((start, index))
            start = index
        index += 1
    if source.slice(start, len(text))[0]:
        ranges.append((start, len(text)))
    return ranges


def _segments(text: str, pinyin: str, work_id: str, mode: str) -> list[dict[str, str]]:
    source = SourceText.from_json(text, pinyin)
    prefix = "line-" if mode == "poem" else "s"
    width = 2 if mode == "poem" else 3
    result = []
    for number, (start, end) in enumerate(_ranges(source, mode), 1):
        zh, py = source.slice(start, end)
        result.append(
            {
                "zh": zh,
                "pinyin": py,
                "id": f"{work_id}-{prefix}{number:0{width}d}",
            }
        )
    return result


def _chapter_id(unit: int, kind: str, number: int) -> str:
    stem = {"识字": "literacy", "汉语拼音": "pinyin"}.get(kind, "reading")
    return f"u{unit:02d}-{stem}-{number:02d}"


def _appendix_contexts(rows: list[dict[str, Any]]) -> dict[int, tuple[int, str, str]]:
    """Return source-row index -> (unit, group, sequence)."""
    result: dict[int, tuple[int, str, str]] = {}
    by_module: dict[str, list[tuple[int, dict[str, Any]]]] = defaultdict(list)
    for index, row in enumerate(rows):
        by_module[row["模块"]].append((index, row))
    for module_rows in by_module.values():
        unit = 1
        for index, row in module_rows:
            sequence = str(row["序号"])
            if sequence.startswith("语文园地"):
                unit = _unit_from_label(sequence)
                result[index] = (unit, row["分组"], sequence)
                unit += 1
            else:
                result[index] = (unit, row["分组"], sequence)
    return result


def _unit_kinds(rows: list[dict[str, Any]]) -> dict[int, str]:
    contexts = _appendix_contexts(rows)
    kinds: dict[int, str] = defaultdict(lambda: "阅读")
    for index, row in enumerate(rows):
        if row["模块"] == "识字表" and row["分组"] in {"识字", "汉语拼音"}:
            kinds[contexts[index][0]] = row["分组"]
    return dict(kinds)


def _lesson_work(
    lesson: dict[str, Any], unit: int, kind: str, chapter_id: str, work_id: str
) -> dict[str, Any]:
    title = lesson["标题"]
    if kind == "汉语拼音":
        content_type = "phonics"
    elif title in POEM_TITLES or any(
        marker in (lesson.get("课题") or "") for marker in ("古诗", "猜字谜")
    ):
        content_type = "poem"
    else:
        content_type = "prose"
    work: dict[str, Any] = {
        "page": lesson["页码"][0],
        "topic": _pair(lesson.get("课题")),
        "title": _pair(title),
        "author": _pair(lesson.get("作者")),
        "dynasty": _pair(lesson.get("年代")),
        "text": _segments(lesson["全文"], lesson["拼音"], work_id, content_type),
    }
    if content_type == "poem":
        work["memorize"] = True
    work["content_type"] = content_type
    work["id"] = work_id
    return work


def _parse_garden_poem(
    text: str, pinyin: str
) -> tuple[str, str, str, str, SourceText] | None:
    for title, (author, dynasty) in sorted(GARDEN_POEMS.items(), key=lambda item: -len(item[0])):
        prefix = f"{title}{author}"
        if text.replace(" ", "").startswith(prefix):
            source = SourceText.from_json(text, pinyin)
            offset = text.find(title) + len(title)
            while offset < len(text) and text[offset].isspace():
                offset += 1
            if author and text.startswith(author, offset):
                offset += len(author)
            while offset < len(text) and text[offset].isspace():
                offset += 1
            body, body_pinyin = source.slice(offset, len(text))
            return title, author, dynasty, body_pinyin, SourceText.from_json(body, body_pinyin)
    return None


def _garden_child(
    unit: int, garden_name: str, row: dict[str, Any], section_number: int
) -> tuple[dict[str, Any], bool]:
    if row.get("名称") == "和大人一起读":
        for title, (author, content_type) in GARDEN_READINGS.items():
            if row["全文"].replace(" ", "").startswith(f"{title}{author}"):
                source = SourceText.from_json(row["全文"], row["拼音"])
                offset = row["全文"].find(title) + len(title)
                while offset < len(source.text) and source.text[offset].isspace():
                    offset += 1
                if author and source.text.startswith(author, offset):
                    offset += len(author)
                while offset < len(source.text) and (
                    source.text[offset].isspace() or source.text[offset] == "①"
                ):
                    offset += 1
                end = source.text.find("①", offset)
                if end < 0:
                    end = len(source.text)
                body, body_pinyin = source.slice(offset, end)
                work_id = f"u{unit:02d}-garden-story-01"
                return (
                    {
                        "topic": _pair(garden_name),
                        "title": _pair(title),
                        "author": _pair(author),
                        "dynasty": {},
                        "text": _segments(body, body_pinyin, work_id, content_type),
                        **({"memorize": True} if content_type == "poem" else {}),
                        "content_type": content_type,
                        "id": work_id,
                    },
                    True,
                )
        raise ValueError(f"无法识别“和大人一起读”标题: unit={unit}, text={row['全文'][:40]}")
    parsed_poem = _parse_garden_poem(row["全文"], row["拼音"])
    if parsed_poem:
        title, author, dynasty, body_pinyin, body = parsed_poem
        work_id = f"u{unit:02d}-garden-poem-01"
        return (
            {
                "topic": _pair(garden_name),
                "title": _pair(title),
                "author": _pair(author),
                "dynasty": _pair(dynasty),
                "text": _segments(body.text, body_pinyin, work_id, "poem"),
                "memorize": True,
                "content_type": "poem",
                "id": work_id,
            },
            True,
        )
    work_id = f"u{unit:02d}-garden-section-{section_number:02d}"
    return (
        {
            "topic": _pair(garden_name),
            "title": _pair(row.get("名称") or "综合练习"),
            "text": _segments(row["全文"], row["拼音"], work_id, "exercise"),
            "content_type": "exercise",
            "id": work_id,
        },
        False,
    )


def _supplementary_child(
    unit: int, parent: str, lesson: dict[str, Any], work_id: str
) -> dict[str, Any]:
    child = _lesson_work(lesson, unit, "阅读", work_id, work_id)
    child["topic"] = _pair(parent)
    return child


def _strip_index_work(work: dict[str, Any]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "name": work.get("name") or work.get("title", {}).get("zh", ""),
        "page": work["page"],
    }
    if "no" in work:
        result["no"] = work["no"]
    if work.get("children") and work.get("content_type") != "garden":
        result["children"] = [
            {"name": child["title"]["zh"], "page": child["page"], "id": child["id"]}
            for child in work["children"]
        ]
    result["id"] = work["id"]
    return result


def _iter_works(contents: list[dict[str, Any]]) -> Iterable[tuple[str, str, dict[str, Any]]]:
    for unit in contents:
        if unit["id"] == "appendix":
            continue
        for chapter in unit["chapters"]:
            if chapter.get("children"):
                for child in chapter["children"]:
                    yield unit["id"], chapter["id"], child
            elif chapter.get("text"):
                yield unit["id"], chapter["id"], chapter


def _target_type(work: dict[str, Any], field: str) -> str:
    if field in {"author", "dynasty", "topic"}:
        return field
    if field == "title":
        return "poem_title" if work["content_type"] == "poem" else "title"
    if work["content_type"] == "poem":
        return "poem_line"
    if work["content_type"] == "exercise":
        return "exercise"
    return "sentence"


def _references(contents: list[dict[str, Any]], needle: str) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    for unit_id, chapter_id, work in _iter_works(contents):
        fields: list[tuple[str, dict[str, str]]] = []
        for field in ("topic", "title", "author", "dynasty"):
            if work.get(field, {}).get("zh"):
                fields.append((field, work[field]))
        fields.extend(("text", segment) for segment in work.get("text", []))
        for field, value in fields:
            text = value["zh"]
            starts = [match.start() for match in re.finditer(re.escape(needle), text)]
            if not starts:
                continue
            syllables = value["pinyin"].split(" ")
            matches = [
                {
                    "start": start,
                    "length": len(needle),
                    "zh": needle,
                    "pinyin": " ".join(syllables[start : start + len(needle)]),
                }
                for start in starts
            ]
            ref: dict[str, Any] = {
                "unit_id": unit_id,
                "chapter_id": chapter_id,
                "work_id": work["id"],
                "target_type": _target_type(work, field),
                "field": field,
            }
            if field == "text":
                ref["segment_id"] = value["id"]
            ref["matches"] = matches
            refs.append(ref)
    return refs


def _recover_character_lists(
    parsed: dict[str, Any],
    contents: list[dict[str, Any]],
    chapter_lookup: dict[tuple[int, str], str],
) -> None:
    """Recover recognition lists that OCR left inside page images only."""
    units = {unit["id"]: unit for unit in contents}
    contexts = _appendix_contexts(parsed["附录"])
    for source_index, row in enumerate(parsed["附录"]):
        sequence = str(row["序号"])
        if row["模块"] != "识字表":
            continue
        values = row["字"]
        if not values or all(_references(contents, value) for value in values):
            continue
        _, group, _ = contexts[source_index]
        if sequence.startswith("语文园地"):
            unit = _unit_from_label(sequence)
            chapter_id = f"u{unit:02d}-garden"
        else:
            expected_stem = {
                "识字": "literacy",
                "汉语拼音": "pinyin",
                "阅读": "reading",
            }.get(group)
            candidates = [
                (candidate_unit, candidate_id)
                for (candidate_unit, candidate_number), candidate_id in chapter_lookup.items()
                if candidate_number == sequence
                and expected_stem is not None
                and f"-{expected_stem}-" in candidate_id
            ]
            if len(candidates) != 1:
                raise KeyError(
                    "无法定位 OCR 遗漏的识字列表: "
                    f"group={group}, no={sequence}, candidates={candidates}"
                )
            unit, chapter_id = candidates[0]
        chapter = next(
            item
            for item in units[f"u{unit:02d}"]["chapters"]
            if item["id"] == chapter_id
        )
        if chapter["content_type"] == "garden":
            target = next(
                (
                    child
                    for child in chapter["children"]
                    if child.get("title", {}).get("zh") == "识字加油站"
                ),
                next(
                    child
                    for child in chapter["children"]
                    if child["content_type"] == "exercise"
                ),
            )
        elif chapter.get("children"):
            target = chapter["children"][0]
        else:
            target = chapter
        target["text"].append(
            {
                "zh": " ".join(values),
                "pinyin": "  ".join(row["拼音"]),
                "id": f"{target['id']}-s{len(target['text']) + 1:03d}",
            }
        )


def _introduced_at(
    unit: int,
    group: str,
    sequence: str,
    chapter_lookup: dict[tuple[int, str], str],
) -> dict[str, str]:
    unit_id = f"u{unit:02d}"
    if sequence.startswith("语文园地"):
        return {"unit_id": unit_id, "chapter_id": f"{unit_id}-garden"}
    key = (unit, sequence)
    if key not in chapter_lookup:
        raise KeyError(f"找不到附录首次出现章节: unit={unit}, group={group}, no={sequence}")
    return {"unit_id": unit_id, "chapter_id": chapter_lookup[key]}


def _appendix_chapters(
    parsed: dict[str, Any],
    contents: list[dict[str, Any]],
    chapter_lookup: dict[tuple[int, str], str],
) -> list[dict[str, Any]]:
    rows = parsed["附录"]
    contexts = _appendix_contexts(rows)
    catalog_pages = {
        row["标题"]: row["页码"][0]
        for row in parsed["目录"]
        if row["类型"] == "附录"
    }
    definitions = (
        ("识字表", "appendix-recognition", "recognition", "字"),
        ("写字表", "appendix-writing", "writing", "字"),
        ("词语表", "appendix-words", "word", "词"),
    )
    chapters = []
    for module, chapter_id, item_prefix, value_key in definitions:
        if module not in catalog_pages or not any(row["模块"] == module for row in rows):
            continue
        items: list[dict[str, Any]] = []
        for source_index, row in enumerate(rows):
            if row["模块"] != module:
                continue
            values = row[value_key]
            pinyin_values = row["拼音"]
            if len(values) != len(pinyin_values):
                raise ValueError(f"{module}/{row['序号']} 的条目与拼音数量不同")
            _, group, sequence = contexts[source_index]
            if sequence.startswith("语文园地"):
                unit = _unit_from_label(sequence)
            else:
                expected_stem = {
                    "识字": "literacy",
                    "汉语拼音": "pinyin",
                    "阅读": "reading",
                }.get(group)
                candidates = [
                    candidate_unit
                    for (candidate_unit, candidate_number), candidate_id in chapter_lookup.items()
                    if candidate_number == sequence
                    and expected_stem is not None
                    and f"-{expected_stem}-" in candidate_id
                ]
                if len(candidates) != 1:
                    raise KeyError(
                        "无法按分组和课号唯一定位附录章节: "
                        f"module={module}, group={group}, no={sequence}, candidates={candidates}"
                    )
                unit = candidates[0]
            introduced = _introduced_at(unit, group, sequence, chapter_lookup)
            for zh, py in zip(values, pinyin_values, strict=True):
                number = len(items) + 1
                item = {
                    "zh": zh,
                    "pinyin": py,
                    "id": f"{item_prefix}-{number:03d}",
                    "refs": _references(contents, zh),
                    "introduced_at": introduced,
                }
                items.append(item)
        chapters.append(
            {
                "name": module,
                "page": catalog_pages[module],
                "text": items,
                "content_type": "appendix",
                "id": chapter_id,
            }
        )
    return chapters


def _validate_generated(document: dict[str, Any]) -> None:
    contents = document["contents"]
    units = {unit["id"] for unit in contents}
    chapters = {chapter["id"] for unit in contents for chapter in unit["chapters"]}
    works: set[str] = set()
    segments: dict[str, dict[str, str]] = {}
    all_ids: list[str] = list(units) + list(chapters)

    def validate_pair(value: dict[str, Any], location: str) -> None:
        if "zh" not in value or "pinyin" not in value:
            return
        zh = value["zh"]
        syllables = value["pinyin"].split(" ") if zh else []
        if len(zh) != len(syllables):
            raise ValueError(
                f"生成结果正文与拼音没有逐字对齐: {location}, "
                f"text={len(zh)}, pinyin={len(syllables)}"
            )

    for unit in contents:
        for chapter in unit["chapters"]:
            candidates = chapter.get("children") or ([chapter] if chapter.get("text") else [])
            for work in candidates:
                works.add(work["id"])
                all_ids.append(work["id"])
                for field in ("topic", "title", "author", "dynasty"):
                    validate_pair(work.get(field, {}), f"{work['id']}.{field}")
                for segment in work.get("text", []):
                    validate_pair(segment, segment["id"])
                    segments[segment["id"]] = segment
                    all_ids.append(segment["id"])

    duplicates = sorted(identifier for identifier in set(all_ids) if all_ids.count(identifier) > 1)
    # A non-collection chapter is also its own work and intentionally shares its ID.
    duplicates = [identifier for identifier in duplicates if identifier not in chapters & works]
    if duplicates:
        raise ValueError(f"生成结果包含重复 ID: {duplicates[:10]}")

    for appendix in contents[-1]["chapters"]:
        for item in appendix["text"]:
            validate_pair(item, item["id"])
            if not item["refs"]:
                raise ValueError(f"附录条目没有正文引用: {item['id']} {item['zh']}")
            introduced = item["introduced_at"]
            if introduced["unit_id"] not in units or introduced["chapter_id"] not in chapters:
                raise ValueError(f"附录首次出现位置无效: {item['id']} {introduced}")
            for ref in item["refs"]:
                if (
                    ref["unit_id"] not in units
                    or ref["chapter_id"] not in chapters
                    or ref["work_id"] not in works
                ):
                    raise ValueError(f"附录正文引用无效: {item['id']} {ref}")
                if "segment_id" in ref and ref["segment_id"] not in segments:
                    raise ValueError(f"附录片段引用无效: {item['id']} {ref}")


def generate(template_path: Path) -> dict[str, Any]:
    root = Path(__file__).resolve().parents[1]
    template = json.loads(template_path.read_text(encoding="utf-8"))
    references = template["reference"]
    resolved = {
        name: _resolve_reference(root, template_path, value)
        for name, value in references.items()
    }
    parsed = json.loads(resolved["python_json"].read_text(encoding="utf-8"))
    unit_kinds = _unit_kinds(parsed["附录"])

    numbered = [
        lesson
        for lesson in parsed["课文"]
        if lesson.get("课号") and not lesson.get("栏目")
    ]
    by_unit_number: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)
    for lesson in numbered:
        by_unit_number[(int(lesson["单元"]), int(lesson["课号"]))].append(lesson)

    garden_by_unit = {int(row["单元"]): row for row in parsed["园地"]}
    supplements_by_unit: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for lesson in parsed["课文"]:
        if lesson.get("栏目") and lesson.get("全文"):
            supplements_by_unit[int(lesson["单元"])].append(lesson)

    contents: list[dict[str, Any]] = []
    introductory = [
        lesson
        for lesson in parsed["课文"]
        if lesson.get("单元") is None and lesson.get("全文")
    ]
    if introductory:
        intro_chapters = []
        for number, lesson in enumerate(introductory, 1):
            chapter_id = f"intro-{number:02d}"
            intro_chapters.append(
                {
                    "name": lesson["标题"],
                    "page": lesson["页码"][0],
                    **_lesson_work(lesson, 0, "阅读", chapter_id, chapter_id),
                }
            )
        contents.append({"name": "入学教育", "chapters": intro_chapters, "id": "intro"})

    chapter_lookup: dict[tuple[int, str], str] = {}
    for unit in sorted(garden_by_unit):
        kind = unit_kinds.get(unit, "阅读")
        unit_id = f"u{unit:02d}"
        unit_node: dict[str, Any] = {
            "name": f"第{CHINESE_NUMERALS[unit]}单元·{kind}",
            "chapters": [],
            "id": unit_id,
        }
        for (_, number), lessons in sorted(
            ((key, value) for key, value in by_unit_number.items() if key[0] == unit),
            key=lambda item: item[0][1],
        ):
            chapter_id = _chapter_id(unit, kind, number)
            chapter_lookup[(unit, str(number))] = chapter_id
            if len(lessons) > 1:
                topic = lessons[0].get("课题") or f"第{number}课"
                children = []
                child_kind = "poem" if "古诗" in topic else "part"
                for child_number, lesson in enumerate(lessons, 1):
                    work_id = f"{chapter_id}-{child_kind}-{child_number:02d}"
                    children.append(_lesson_work(lesson, unit, kind, chapter_id, work_id))
                chapter = {
                    "name": topic,
                    "no": number,
                    "page": lessons[0]["页码"][0],
                    "children": children,
                    "content_type": "collection",
                    "id": chapter_id,
                }
            else:
                lesson = lessons[0]
                chapter = {
                    "name": lesson["标题"],
                    "no": number,
                    **_lesson_work(lesson, unit, kind, chapter_id, chapter_id),
                }
            unit_node["chapters"].append(chapter)

        garden = garden_by_unit[unit]
        garden_id = f"{unit_id}-garden"
        garden_children: list[dict[str, Any]] = []
        section_number = 1
        for row in garden["栏目"]:
            # Empty names are partial OCR echoes of the following named section,
            # not independent textbook columns.
            if not row.get("名称"):
                continue
            child, is_poem = _garden_child(unit, garden["标题"], row, section_number)
            garden_children.append(child)
            if not is_poem:
                section_number += 1
        for lesson in supplements_by_unit[unit]:
            if lesson.get("栏目") in {"我爱阅读", "和大人一起读"}:
                work_id = f"{garden_id}-story-01"
                garden_children.append(
                    _supplementary_child(unit, garden["标题"], lesson, work_id)
                )
            elif lesson.get("栏目") == "口语交际":
                work_id = f"{garden_id}-section-{section_number:02d}"
                garden_children.append(
                    {
                        "topic": _pair(garden["标题"]),
                        "title": _pair(lesson["标题"]),
                        "text": _segments(
                            lesson["全文"], lesson["拼音"], work_id, "exercise"
                        ),
                        "content_type": "exercise",
                        "id": work_id,
                    }
                )
                section_number += 1
        unit_node["chapters"].append(
            {
                "name": garden["标题"],
                "page": garden["页码"][0],
                "children": garden_children,
                "content_type": "garden",
                "id": garden_id,
            }
        )

        for lesson in supplements_by_unit[unit]:
            if lesson.get("栏目") != "快乐读书吧":
                continue
            parent_id = f"{unit_id}-reading-club"
            work_id = f"{parent_id}-story-01"
            child = _supplementary_child(unit, "快乐读书吧", lesson, work_id)
            unit_node["chapters"].append(
                {
                    "name": "快乐读书吧",
                    "page": lesson["页码"][0],
                    "children": [child],
                    "content_type": "reading_guide",
                    "id": parent_id,
                }
            )
        contents.append(unit_node)

    _recover_character_lists(parsed, contents, chapter_lookup)
    appendix = {
        "name": "附录",
        "chapters": _appendix_chapters(parsed, contents, chapter_lookup),
        "id": "appendix",
    }
    contents.append(appendix)
    index = [
        {
            "name": unit["name"],
            "chapters": [_strip_index_work(chapter) for chapter in unit["chapters"]],
            "id": unit["id"],
        }
        for unit in contents
    ]
    result = {
        "schema_version": 2,
        "reference": copy.deepcopy(references),
        "index": index,
        "contents": contents,
    }
    _validate_generated(result)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", type=Path, help="json_reviewed schema-v2 template/output")
    parser.add_argument("--output", type=Path, help="write elsewhere instead of replacing file")
    args = parser.parse_args()
    result = generate(args.file.resolve())
    output = (args.output or args.file).resolve()
    output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
