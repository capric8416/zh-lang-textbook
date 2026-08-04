#!/usr/bin/env python3
"""Migrate and validate textbook polyphone JSON files."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from pathlib import Path


GROUPS = ("本册出现", "常用", "不常用")
FIELDS = {"读音", "语境", "例子", "快速判断"}

GUIDANCE: dict[tuple[str, str], tuple[str, list[str], str]] = {
    ("的", "de"): ("修饰名词，表示所属、性质或说明对象时作结构助词。", ["我的书", "美丽的花", "写的文章"], "放在名词前作修饰语时，通常读轻声 de。"),
    ("的", "dí"): ("表示确实、实在，主要用于“的确”。", ["的确", "的的确确", "的确如此"], "能换成“确实”时，读 dí。"),
    ("的", "dì"): ("表示目标、箭靶或命中的对象。", ["目的", "有的放矢", "一语中的"], "表示目标或命中目标时，读 dì。"),
    ("的", "dī"): ("用于出租车相关的口语词。", ["的士", "打的", "的哥"], "表示出租车时，读 dī。"),
    ("地", "de"): ("放在动词或形容词前，标明动作的方式、状态。", ["高兴地说", "慢慢地走", "认真地学习"], "位于动作前，能回答“怎样做”时，通常读轻声 de。"),
    ("地", "dì"): ("表示土地、地点、地面或空间。", ["土地", "地方", "地面"], "表示实际地点或土地时，读 dì。"),
    ("得", "de"): ("放在动词或形容词后作补语标志，也用于“觉得、显得”等词。", ["跑得快", "写得好", "觉得"], "位于动作后，补充程度或结果时，通常读轻声 de。"),
    ("得", "dé"): ("表示获得、取得或得到。", ["得到", "获得", "得分"], "能换成“获得”时，通常读 dé。"),
    ("得", "děi"): ("表示必须、需要或对情况的估计。", ["我得走了", "非得完成", "得三天"], "能换成“必须”或“需要”时，读 děi。"),
}


def generated_guidance(
    char: str, pronunciation: str, group: str, examples: list[str]
) -> tuple[str, list[str], str]:
    special = GUIDANCE.get((char, pronunciation))
    if special:
        return special
    if examples:
        joined = "、".join(examples)
        context = (
            f"本册在“{joined}”等词语中使用这个读音。"
            if group == "本册出现"
            else f"常见于“{joined}”等固定词语或人名、地名中。"
        )
        return context, examples, f"看到“{joined}”等词语时，读 {pronunciation}；其他搭配结合词义判断。"
    return (
        "罕见、古语或词典保留读音，本册没有可用词例。",
        [],
        f"本册通常不读 {pronunciation}；遇到生僻词时查词典确认。",
    )


def normalize_entry(char: str, group: str, entry: object) -> dict:
    if not isinstance(entry, dict):
        raise ValueError(f"{char}/{group}: 读音条目不是对象")
    if set(entry) == FIELDS:
        return entry

    pronunciation = entry.get("读音") or entry.get("拼音")
    if not isinstance(pronunciation, str) or not pronunciation:
        raise ValueError(f"{char}/{group}: 缺少读音")
    examples = entry.get("例子", entry.get("组词", []))
    if not isinstance(examples, list) or not all(isinstance(x, str) for x in examples):
        raise ValueError(f"{char}/{pronunciation}: 例子必须是字符串数组")
    context, examples, quick_rule = generated_guidance(
        char, pronunciation, group, examples
    )
    return {
        "读音": pronunciation,
        "语境": entry.get("语境") or context,
        "例子": examples,
        "快速判断": entry.get("快速判断") or quick_rule,
    }


def normalize_document(data: object) -> dict:
    if not isinstance(data, dict) or not isinstance(data.get("多音字"), list):
        raise ValueError("根对象必须包含多音字数组")
    for row in data["多音字"]:
        if not isinstance(row, dict) or not isinstance(row.get("字"), str) or not row["字"]:
            raise ValueError("每个多音字条目必须包含字")
        char = row["字"]
        for group in GROUPS:
            entries = row.get(group, [])
            if not isinstance(entries, list):
                raise ValueError(f"{char}/{group}: 必须是数组")
            row[group] = [normalize_entry(char, group, entry) for entry in entries]
    data["多音字数量"] = len(data["多音字"])
    data["读音数量"] = sum(
        len(row.get(group, [])) for row in data["多音字"] for group in GROUPS
    )
    return data


def validate_document(data: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict) or not isinstance(data.get("多音字"), list):
        return ["根对象必须包含多音字数组"]
    rows = data["多音字"]
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("字"), str) or not row["字"]:
            errors.append("每个多音字条目必须包含字")
            continue
        char = row["字"]
        seen: set[str] = set()
        for group in GROUPS:
            entries = row.get(group)
            if not isinstance(entries, list):
                errors.append(f"{char}/{group}: 必须是数组")
                continue
            for entry in entries:
                if not isinstance(entry, dict):
                    errors.append(f"{char}/{group}: 读音条目不是对象")
                    continue
                if set(entry) != FIELDS:
                    errors.append(f"{char}/{group}: 字段必须恰好为 {sorted(FIELDS)}")
                pronunciation = entry.get("读音")
                if not isinstance(pronunciation, str) or not pronunciation:
                    errors.append(f"{char}/{group}: 读音为空")
                    continue
                if pronunciation in seen:
                    errors.append(f"{char}: 重复读音 {pronunciation}")
                seen.add(pronunciation)
                if not isinstance(entry.get("语境"), str) or not entry["语境"]:
                    errors.append(f"{char}/{pronunciation}: 语境为空")
                examples = entry.get("例子")
                if not isinstance(examples, list) or not all(isinstance(x, str) for x in examples):
                    errors.append(f"{char}/{pronunciation}: 例子必须是字符串数组")
                if not isinstance(entry.get("快速判断"), str) or not entry["快速判断"]:
                    errors.append(f"{char}/{pronunciation}: 快速判断为空")
    if data.get("多音字数量") != len(rows):
        errors.append("多音字数量与实际条目数不一致")
    reading_count = sum(
        len(row.get(group, []))
        for row in rows
        if isinstance(row, dict)
        for group in GROUPS
        if isinstance(row.get(group), list)
    )
    if data.get("读音数量") != reading_count:
        errors.append("读音数量与实际条目数不一致")
    return errors


def atomic_write(path: Path, data: dict) -> None:
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        handle.write(text)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def process(path: Path, check: bool) -> bool:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if check:
            errors = validate_document(data)
            if errors:
                for error in errors:
                    print(f"{path}: {error}", file=sys.stderr)
                return False
            print(f"{path}: OK")
            return True
        normalized = normalize_document(data)
        errors = validate_document(normalized)
        if errors:
            raise ValueError("；".join(errors))
        atomic_write(path, normalized)
        print(f"{path}: 已整理 {normalized['多音字数量']} 字/{normalized['读音数量']} 读音")
        return True
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"{path}: {error}", file=sys.stderr)
        return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="整理并校验多音字 JSON 表")
    parser.add_argument("files", nargs="+", type=Path, help="一个或多个 *polyphone.json")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--in-place", action="store_true", help="原地迁移为新结构")
    mode.add_argument("--check", action="store_true", help="只校验，不写文件")
    args = parser.parse_args(argv)
    results = [process(path, args.check) for path in args.files]
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
