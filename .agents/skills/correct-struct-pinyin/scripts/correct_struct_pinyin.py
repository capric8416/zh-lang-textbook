#!/usr/bin/env python3
"""Audit and apply reviewed polyphone corrections to aligned struct JSON."""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterator


GROUPS = ("本册出现", "常用", "不常用")


@dataclass(frozen=True)
class Rule:
    char: str
    reading: str
    phrase: str
    group: str


@dataclass
class Unit:
    path: tuple[object, ...]
    text: str
    tokens: list[str]
    save: Callable[[list[str]], None]


def read_json(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path}: JSON 根节点不是对象")
    return data


def paired_struct(polyphone_path: Path) -> Path:
    suffix = "-polyphone.json"
    if not polyphone_path.name.endswith(suffix):
        raise ValueError(f"文件名必须以 {suffix} 结尾：{polyphone_path}")
    return polyphone_path.with_name(
        polyphone_path.name[: -len(suffix)] + "-struct.json"
    )


def load_rules(data: dict) -> tuple[dict[str, list[Rule]], dict[str, set[str]]]:
    rows = data.get("多音字")
    if not isinstance(rows, list):
        raise ValueError("多音字表缺少多音字数组")
    rules: dict[str, list[Rule]] = {}
    readings: dict[str, set[str]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("字"), str):
            raise ValueError("多音字条目缺少字")
        char = row["字"]
        for group in GROUPS:
            entries = row.get(group, [])
            if not isinstance(entries, list):
                raise ValueError(f"{char}/{group} 不是数组")
            for entry in entries:
                if not isinstance(entry, dict):
                    raise ValueError(f"{char}/{group} 读音条目不是对象")
                reading = entry.get("读音") or entry.get("拼音")
                examples = entry.get("例子", entry.get("组词", []))
                if not isinstance(reading, str) or not reading:
                    raise ValueError(f"{char}/{group} 缺少读音")
                if not isinstance(examples, list):
                    raise ValueError(f"{char}/{reading} 例子不是数组")
                readings.setdefault(char, set()).add(reading)
                for phrase in examples:
                    if not isinstance(phrase, str) or len(phrase) < 2 or char not in phrase:
                        continue
                    rule = Rule(char, reading, phrase, group)
                    if rule not in rules.setdefault(char, []):
                        rules[char].append(rule)
    return rules, readings


def aligned_units(node: object, path: tuple[object, ...] = ()) -> Iterator[Unit]:
    if isinstance(node, dict):
        text = node.get("全文")
        pinyin = node.get("拼音")
        if isinstance(text, str) and isinstance(pinyin, str):
            tokens = pinyin.split(" ")
            if len(tokens) == len(text):
                yield Unit(
                    path + ("全文",),
                    text,
                    tokens,
                    lambda values, target=node: target.__setitem__("拼音", " ".join(values)),
                )
        if isinstance(pinyin, list):
            for field in ("字", "词"):
                values = node.get(field)
                if not isinstance(values, list) or len(values) != len(pinyin):
                    continue
                for index, (value, pronunciation) in enumerate(zip(values, pinyin)):
                    if not isinstance(value, str) or not isinstance(pronunciation, str):
                        continue
                    tokens = pronunciation.split(" ")
                    if len(tokens) == len(value):
                        yield Unit(
                            path + (field, index),
                            value,
                            tokens,
                            lambda items, target=pinyin, position=index: target.__setitem__(position, " ".join(items)),
                        )
                break
        for key, value in node.items():
            yield from aligned_units(value, path + (key,))
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from aligned_units(value, path + (index,))


def evidence(text: str, rules: dict[str, list[Rule]]) -> dict[int, list[Rule]]:
    result: dict[int, list[Rule]] = {}
    for char, char_rules in rules.items():
        if char not in text:
            continue
        for rule in char_rules:
            start = text.find(rule.phrase)
            while start >= 0:
                for offset, current in enumerate(rule.phrase):
                    if current == char:
                        result.setdefault(start + offset, []).append(rule)
                start = text.find(rule.phrase, start + 1)
    return result


def display_path(path: tuple[object, ...]) -> str:
    return "/".join(str(part) for part in path)


def sentence_context(text: str, index: int, limit: int = 100) -> str:
    """Return the sentence containing index, cropped only when it is unusually long."""
    stops = "。！？!?；;\n"
    left = max(text.rfind(stop, 0, index) for stop in stops) + 1
    ends = [text.find(stop, index) for stop in stops]
    ends = [position for position in ends if position >= 0]
    right = min(ends) + 1 if ends else len(text)
    context = text[left:right].strip()
    relative = index - left
    if len(context) <= limit:
        return context
    start = max(0, relative - limit // 2)
    end = min(len(context), start + limit)
    start = max(0, end - limit)
    return ("…" if start else "") + context[start:end] + ("…" if end < len(context) else "")


def record_key(item: dict) -> tuple[tuple[object, ...], object, object]:
    path = item.get("路径", [])
    return tuple(path) if isinstance(path, list) else (), item.get("序"), item.get("字")


def markdown_escape(value: object) -> str:
    if isinstance(value, list):
        text = "/".join(str(part) for part in value)
    else:
        text = "" if value is None else str(value)
    return text.replace("\\", "\\\\").replace("|", "\\|").replace("\n", "<br>")


def report_rows(report: dict) -> list[tuple[str, dict]]:
    corrected = report.get("已修正", report.get("修正", []))
    unchanged = report.get("保留不改", [])
    manual = report.get("人工复核", [])
    corrected = corrected if isinstance(corrected, list) else []
    unchanged = unchanged if isinstance(unchanged, list) else []
    manual = manual if isinstance(manual, list) else []

    decided = {
        record_key(item)
        for items in (corrected, unchanged, manual)
        for item in items
        if isinstance(item, dict)
    }
    remaining: list[dict] = []
    for field in ("候选", "冲突"):
        items = report.get(field, [])
        if not isinstance(items, list):
            continue
        remaining.extend(
            item
            for item in items
            if isinstance(item, dict) and record_key(item) not in decided
        )
    return (
        [("已修正", item) for item in corrected if isinstance(item, dict)]
        + [("保留不改", item) for item in unchanged if isinstance(item, dict)]
        + [("人工复核", item) for item in manual if isinstance(item, dict)]
        + [("人工复核", item) for item in remaining]
    )


def render_markdown(report: dict, output_path: Path) -> None:
    rows = report_rows(report)
    counts = {
        status: sum(1 for current, _ in rows if current == status)
        for status in ("已修正", "保留不改", "人工复核")
    }
    title = Path(str(report.get("结构文件", "struct.json"))).name
    lines = [
        f"# {title} 注音校正报告",
        "",
        f"- 已修正：{counts['已修正']} 处",
        f"- 保留不改：{counts['保留不改']} 处",
        f"- 人工复核：{counts['人工复核']} 处",
        "",
        "| 位置索引 | 所在的句子上下文 | 字 | 原注音 | 修正后的注音 | 状态 | 依据/说明 |",
        "|---|---|---|---|---|---|---|",
    ]
    for status, item in rows:
        location = f"{display_path(tuple(item.get('路径', [])))}[{item.get('序', '')}]"
        original = item.get("原拼音", "")
        suggested = item.get("新拼音", item.get("建议拼音", ""))
        if status == "保留不改":
            revised = original
        elif status == "人工复核":
            revised = f"待定（{markdown_escape(suggested)}）"
        else:
            revised = suggested
        explanation = item.get("依据", item.get("说明", ""))
        if not explanation:
            examples = item.get("词例", [])
            explanation = "词例：" + "、".join(examples) if isinstance(examples, list) else ""
        lines.append(
            "| "
            + " | ".join(
                markdown_escape(value)
                for value in (
                    location,
                    item.get("上下文", ""),
                    item.get("字", ""),
                    original,
                    revised,
                    status,
                    explanation,
                )
            )
            + " |"
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def candidate(
    unit: Unit,
    index: int,
    rules: list[Rule],
    allowed: dict[str, set[str]],
) -> tuple[str, dict] | None:
    char = unit.text[index]
    current = unit.tokens[index]
    # 表中没有轻声/儿化等原书标注时，保留原值，不把字典本调强行覆盖。
    if current not in allowed.get(char, set()):
        return None
    longest = max(len(rule.phrase) for rule in rules)
    strongest = [rule for rule in rules if len(rule.phrase) == longest]
    choices = sorted({rule.reading for rule in strongest})
    record = {
        "路径": list(unit.path),
        "序": index,
        "字": char,
        "原拼音": current,
        "建议拼音": choices[0] if len(choices) == 1 else choices,
        "词例": sorted({rule.phrase for rule in strongest}),
        "来源分组": sorted({rule.group for rule in strongest}),
        "上下文": sentence_context(unit.text, index),
    }
    if len(choices) > 1:
        return "冲突", record
    if choices[0] == current:
        return None
    return "候选", record


def atomic_write(path: Path, data: dict) -> None:
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        handle.write(text)
        temporary = Path(handle.name)
    os.replace(temporary, path)


def audit(polyphone_path: Path, report_dir: Path) -> bool:
    try:
        struct_path = paired_struct(polyphone_path)
        polyphone = read_json(polyphone_path)
        struct = read_json(struct_path)
        rules, allowed = load_rules(polyphone)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(error, file=sys.stderr)
        return False

    candidates: list[dict] = []
    conflicts: list[dict] = []
    units = list(aligned_units(struct))
    for unit in units:
        for index, matched in evidence(unit.text, rules).items():
            result = candidate(unit, index, matched, allowed)
            if result is None:
                continue
            kind, record = result
            (candidates if kind == "候选" else conflicts).append(record)

    report = {
        "多音字表": str(polyphone_path),
        "结构文件": str(struct_path),
        "注音单元数": len(units),
        "候选": candidates,
        "冲突": conflicts,
        "修正": [],
        "保留不改": [],
        "人工复核": [],
    }
    report_dir.mkdir(parents=True, exist_ok=True)
    suffix = "-polyphone.json"
    report_path = report_dir / (
        polyphone_path.name[: -len(suffix)] + "-pinyin-audit.json"
    )
    atomic_write(report_path, report)
    markdown_path = report_path.with_name(
        report_path.name.replace("-pinyin-audit.json", "-pinyin-report.md")
    )
    render_markdown(report, markdown_path)
    print(
        f"{report_path}: {len(units)} 单元，候选 {len(candidates)}，"
        f"冲突 {len(conflicts)}；报告 {markdown_path}"
    )
    return True


def resolve_unit(data: dict, path: list[object]) -> Unit:
    if not path:
        raise ValueError("修正路径为空")
    node: object = data
    for part in path[:-1]:
        if isinstance(node, dict) and isinstance(part, str):
            node = node[part]
        elif isinstance(node, list) and isinstance(part, int):
            node = node[part]
        else:
            raise ValueError(f"无法解析路径：{path}")

    last = path[-1]
    if last == "全文" and isinstance(node, dict):
        text = node.get("全文")
        pinyin = node.get("拼音")
        if isinstance(text, str) and isinstance(pinyin, str):
            tokens = pinyin.split(" ")
            if len(tokens) == len(text):
                return Unit(
                    tuple(path),
                    text,
                    tokens,
                    lambda values, target=node: target.__setitem__("拼音", " ".join(values)),
                )

    if isinstance(last, int) and len(path) >= 2:
        field = path[-2]
        parent: object = data
        for part in path[:-2]:
            parent = parent[part]  # type: ignore[index]
        if isinstance(parent, dict) and field in ("字", "词"):
            values = parent.get(field)
            pinyin = parent.get("拼音")
            if isinstance(values, list) and isinstance(pinyin, list):
                text = values[last]
                pronunciation = pinyin[last]
                if isinstance(text, str) and isinstance(pronunciation, str):
                    tokens = pronunciation.split(" ")
                    if len(tokens) == len(text):
                        return Unit(
                            tuple(path),
                            text,
                            tokens,
                            lambda items, target=pinyin, position=last: target.__setitem__(position, " ".join(items)),
                        )
    raise ValueError(f"路径不是可编辑注音单元：{path}")


def apply_plan(plan_path: Path) -> bool:
    try:
        plan = read_json(plan_path)
        struct_path = Path(plan["结构文件"])
        polyphone_path = Path(plan["多音字表"])
        corrections = plan.get("修正")
        if not isinstance(corrections, list):
            raise ValueError("计划的修正字段不是数组")
        struct = read_json(struct_path)
        _, allowed = load_rules(read_json(polyphone_path))

        prepared: list[tuple[Unit, int, str]] = []
        unit_cache: dict[tuple[object, ...], Unit] = {}
        for item in corrections:
            if not isinstance(item, dict):
                raise ValueError("修正条目不是对象")
            correction_path = tuple(item["路径"])
            unit = unit_cache.get(correction_path)
            if unit is None:
                unit = resolve_unit(struct, item["路径"])
                unit_cache[correction_path] = unit
            index = item["序"]
            char = item["字"]
            old = item["原拼音"]
            new = item.get("新拼音", item.get("建议拼音"))
            if not isinstance(index, int) or not 0 <= index < len(unit.text):
                raise ValueError(f"序号越界：{item}")
            if unit.text[index] != char:
                raise ValueError(f"字符前置条件失败：{unit.text[index]} != {char}")
            if unit.tokens[index] != old:
                raise ValueError(f"拼音前置条件失败：{unit.tokens[index]} != {old}")
            if not isinstance(new, str) or new not in allowed.get(char, set()):
                raise ValueError(f"建议拼音不在多音字表中：{char} {new}")
            item["上下文"] = sentence_context(unit.text, index)
            prepared.append((unit, index, new))

        for unit, index, new in prepared:
            unit.tokens[index] = new
        for unit in unit_cache.values():
            unit.save(unit.tokens)
        if prepared:
            atomic_write(struct_path, struct)
        plan["已修正"] = corrections
        atomic_write(plan_path, plan)
        render_markdown(
            plan,
            plan_path.with_name(plan_path.stem + "-report.md"),
        )
        print(f"{struct_path}: 已应用 {len(prepared)} 处修正")
        return True
    except (KeyError, IndexError, OSError, json.JSONDecodeError, ValueError) as error:
        print(f"{plan_path}: {error}", file=sys.stderr)
        return False


def render_plan(plan_path: Path, report_dir: Path | None) -> bool:
    try:
        report = read_json(plan_path)
        struct_name = Path(str(report.get("结构文件", plan_path.stem))).name
        output_name = struct_name.replace("-struct.json", "-pinyin-report.md")
        output_path = (report_dir or plan_path.parent) / output_name
        render_markdown(report, output_path)
        print(f"{output_path}: 已生成 {len(report_rows(report))} 行")
        return True
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"{plan_path}: {error}", file=sys.stderr)
        return False


def finalize_report(
    audit_path: Path,
    approved_by_struct: dict[str, list[dict]],
    report_dir: Path,
) -> bool:
    try:
        report = read_json(audit_path)
        struct_file = str(report["结构文件"])
        struct = read_json(Path(struct_file))
        corrections = approved_by_struct.get(struct_file, [])
        candidates = report.get("候选", [])
        conflicts = report.get("冲突", [])
        if not isinstance(candidates, list) or not isinstance(conflicts, list):
            raise ValueError("审计报告的候选或冲突不是数组")

        evidence = {
            record_key(item): item
            for items in (candidates, conflicts)
            for item in items
            if isinstance(item, dict)
        }
        corrected: list[dict] = []
        for correction in corrections:
            key = record_key(correction)
            merged = dict(evidence.get(key, {}))
            merged.update(correction)
            corrected.append(merged)
        corrected_keys = {record_key(item) for item in corrected}

        report["已修正"] = corrected
        report["保留不改"] = [
            item
            for item in candidates
            if isinstance(item, dict) and record_key(item) not in corrected_keys
        ]
        report["人工复核"] = [
            item
            for item in conflicts
            if isinstance(item, dict) and record_key(item) not in corrected_keys
        ]
        report["修正"] = []

        for items in (
            report["已修正"],
            report["保留不改"],
            report["人工复核"],
        ):
            for item in items:
                unit = resolve_unit(struct, item["路径"])
                item["上下文"] = sentence_context(unit.text, item["序"])

        output_name = Path(struct_file).name.replace(
            "-struct.json", "-pinyin-report.md"
        )
        output_path = report_dir / output_name
        render_markdown(report, output_path)
        print(
            f"{output_path}: 已修正 {len(corrected)}，"
            f"保留不改 {len(report['保留不改'])}，人工复核 {len(report['人工复核'])}"
        )
        return True
    except (KeyError, OSError, json.JSONDecodeError, ValueError) as error:
        print(f"{audit_path}: {error}", file=sys.stderr)
        return False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="审计并应用 struct.json 多音字注音修正")
    parser.add_argument("files", nargs="*", type=Path, help="一个或多个 *polyphone.json")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--audit-dir", type=Path, help="生成候选报告的目录")
    mode.add_argument("--apply-plan", nargs="+", type=Path, help="应用已审核的计划文件")
    mode.add_argument("--render-report", nargs="+", type=Path, help="从审核记录生成 Markdown 报告")
    mode.add_argument("--finalize-report", nargs="+", type=Path, help="合并初始审计和已批准计划，生成最终报告")
    parser.add_argument("--approved-plan", nargs="+", type=Path, help="--finalize-report 使用的已批准计划")
    parser.add_argument("--report-dir", type=Path, help="Markdown 报告输出目录")
    args = parser.parse_args(argv)

    if args.audit_dir:
        if not args.files:
            parser.error("--audit-dir 需要至少一个 polyphone.json")
        results = [audit(path, args.audit_dir) for path in args.files]
    elif args.apply_plan:
        if args.files:
            parser.error("--apply-plan 不接受前置 polyphone.json 参数")
        results = [apply_plan(path) for path in args.apply_plan]
    elif args.render_report:
        if args.files:
            parser.error("--render-report 不接受前置 polyphone.json 参数")
        results = [render_plan(path, args.report_dir) for path in args.render_report]
    else:
        if args.files:
            parser.error("--finalize-report 不接受前置 polyphone.json 参数")
        if not args.approved_plan or not args.report_dir:
            parser.error("--finalize-report 需要 --approved-plan 和 --report-dir")
        approved_by_struct: dict[str, list[dict]] = {}
        for path in args.approved_plan:
            plan = read_json(path)
            corrections = plan.get("已修正", plan.get("修正", []))
            if not isinstance(corrections, list):
                parser.error(f"{path}: 修正不是数组")
            approved_by_struct.setdefault(str(plan["结构文件"]), []).extend(corrections)
        results = [
            finalize_report(path, approved_by_struct, args.report_dir)
            for path in args.finalize_report
        ]
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
