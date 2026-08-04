"""从 struct.json 提取多音字、实际读音和组词。

多音字及其全部读音以 pypinyin 的单字词典为准；某个读音是否在本册出现，
以 struct.json 中已有的逐字注音为准。组词优先使用本册文本中的词，缺少时
从 pypinyin 词语词典反查，并用 jieba 词频选择较常见的短词。
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import warnings
from collections import defaultdict
from pathlib import Path
from typing import Iterable

with warnings.catch_warnings():
    warnings.simplefilter("ignore", SyntaxWarning)
    import jieba

from pypinyin import Style, pinyin
from pypinyin.phrases_dict import phrases_dict

jieba.setLogLevel(logging.ERROR)


# 结构助词不能只靠词例说明，单独给出适合小学生使用的语法判断规则。
READING_GUIDANCE: dict[tuple[str, str], tuple[str, list[str], str]] = {
    ("的", "de"): (
        "修饰名词，表示所属、性质或说明对象时作结构助词。",
        ["我的书", "美丽的花", "写的文章"],
        "放在名词前作修饰语时，通常读轻声 de。",
    ),
    ("的", "dí"): (
        "表示确实、实在，主要用于“的确”。",
        ["的确", "的的确确", "的确如此"],
        "能换成“确实”时，读 dí。",
    ),
    ("的", "dì"): (
        "表示目标、箭靶或命中的对象。",
        ["目的", "有的放矢", "一语中的"],
        "表示目标或命中目标时，读 dì。",
    ),
    ("的", "dī"): (
        "用于出租车相关的口语词。",
        ["的士", "打的", "的哥"],
        "表示出租车时，读 dī。",
    ),
    ("地", "de"): (
        "放在动词或形容词前，标明动作的方式、状态。",
        ["高兴地说", "慢慢地走", "认真地学习"],
        "位于动作前，能回答“怎样做”时，通常读轻声 de。",
    ),
    ("地", "dì"): (
        "表示土地、地点、地面或空间。",
        ["土地", "地方", "地面"],
        "表示实际地点或土地时，读 dì。",
    ),
    ("得", "de"): (
        "放在动词或形容词后作补语标志，也用于“觉得、显得”等词。",
        ["跑得快", "写得好", "觉得"],
        "位于动作后，补充程度或结果时，通常读轻声 de。",
    ),
    ("得", "dé"): (
        "表示获得、取得或得到。",
        ["得到", "获得", "得分"],
        "能换成“获得”时，通常读 dé。",
    ),
    ("得", "děi"): (
        "表示必须、需要或对情况的估计。",
        ["我得走了", "非得完成", "得三天"],
        "能换成“必须”或“需要”时，读 děi。",
    ),
}


def _is_han(ch: str) -> bool:
    return len(ch) == 1 and "一" <= ch <= "鿿"


def _unique(values: Iterable[str]) -> list[str]:
    return list(dict.fromkeys(values))


def _all_chars(data: object) -> list[str]:
    """按首次出现顺序收集所有非拼音字段里的汉字。"""
    result: list[str] = []
    seen: set[str] = set()

    def visit(value: object, key: str = "") -> None:
        if key == "拼音":
            return
        if isinstance(value, dict):
            for child_key, child in value.items():
                visit(child, child_key)
        elif isinstance(value, list):
            for child in value:
                visit(child, key)
        elif isinstance(value, str):
            for ch in value:
                if _is_han(ch) and ch not in seen:
                    seen.add(ch)
                    result.append(ch)

    visit(data)
    return result


def _aligned_units(data: object) -> Iterable[tuple[str, list[str]]]:
    """产出 struct.json 中有明确逐字对应关系的（文本，拼音）单元。"""
    if isinstance(data, dict):
        text = data.get("全文")
        py = data.get("拼音")
        if isinstance(text, str) and isinstance(py, str):
            tokens = py.split(" ")
            if len(tokens) == len(text):
                yield text, tokens

        if isinstance(py, list):
            for field in ("字", "词"):
                values = data.get(field)
                if not isinstance(values, list) or len(values) != len(py):
                    continue
                for value, pronunciation in zip(values, py):
                    if not isinstance(value, str) or not isinstance(pronunciation, str):
                        continue
                    tokens = pronunciation.split(" ")
                    if len(tokens) == len(value):
                        yield value, tokens

        for child in data.values():
            yield from _aligned_units(child)
    elif isinstance(data, list):
        for child in data:
            yield from _aligned_units(child)


def _words_at(text: str) -> dict[int, str]:
    """用 jieba 分词，返回字符下标到所在短词的映射。"""
    result: dict[int, str] = {}
    offset = 0
    for word in jieba.lcut(text):
        end = offset + len(word)
        if 2 <= len(word) <= 4 and all(_is_han(ch) for ch in word):
            for index in range(offset, end):
                result[index] = word
        offset = end
    return result


def _book_readings_and_words(
    data: object,
) -> tuple[dict[str, set[str]], dict[tuple[str, str], list[str]]]:
    readings: dict[str, set[str]] = defaultdict(set)
    words: dict[tuple[str, str], list[str]] = defaultdict(list)
    for text, tokens in _aligned_units(data):
        word_at = _words_at(text)
        for index, (ch, py) in enumerate(zip(text, tokens)):
            if not _is_han(ch) or not py:
                continue
            readings[ch].add(py)
            word = word_at.get(index)
            if word and word not in words[(ch, py)]:
                words[(ch, py)].append(word)
    return readings, words


def _dictionary_words(
    wanted: set[str],
    readings: dict[str, set[str]],
    book_words: dict[tuple[str, str], list[str]],
) -> dict[tuple[str, str], list[str]]:
    """汇总候选词，按日常书面语词频从高到低选择。"""
    candidates: dict[tuple[str, str], list[tuple[int, int, str]]] = defaultdict(list)
    candidate_words = set(phrases_dict)

    # pypinyin 的短语表擅长区分读音，但会漏掉“穴位”一类常用词。再从 jieba
    # 通用词频表中补齐全部相关候选。候选集不随 limit 改变，保证限制为 N 时
    # 得到的结果严格等于不限量结果按常用度排序后的前 N 个。
    jieba.initialize()
    candidate_words.update(
        word
        for word in jieba.dt.FREQ
        if 2 <= len(word) <= 4
        and all(_is_han(ch) for ch in word)
        and wanted.intersection(word)
    )

    for word in candidate_words:
        if not (2 <= len(word) <= 4 and all(_is_han(ch) for ch in word)):
            continue
        relevant = wanted.intersection(word)
        if not relevant:
            continue
        tokens = [item[0] for item in pinyin(word, style=Style.TONE, heteronym=False)]
        if len(tokens) != len(word):
            continue
        frequency = jieba.get_FREQ(word) or 0
        for ch in relevant:
            for index, current in enumerate(word):
                if current == ch and tokens[index] in readings[ch]:
                    candidates[(ch, tokens[index])].append(
                        (-frequency, len(word), word)
                    )

    # 本册分出的词也参与同一套词频排序，不因“恰好在本册出现”而获得额外优先级。
    for key, words in book_words.items():
        if key[0] not in wanted or key[1] not in readings[key[0]]:
            continue
        for word in words:
            candidates[key].append((-(jieba.get_FREQ(word) or 0), len(word), word))

    result: dict[tuple[str, str], list[str]] = {}
    for key, values in candidates.items():
        ordered = sorted(set(values))
        words = _unique(word for _, _, word in ordered)
        result[key] = words
    return result


def _guidance(
    ch: str, py: str, group: str, examples: list[str]
) -> tuple[str, list[str], str]:
    """把词例整理成“语境、例子、快速判断”，特殊语法字优先使用人工规则。"""
    special = READING_GUIDANCE.get((ch, py))
    if special:
        return special

    if examples:
        words = "、".join(examples)
        context = (
            f"本册在“{words}”等词语中使用这个读音。"
            if group == "本册出现"
            else f"常见于“{words}”等固定词语或人名、地名中。"
        )
        return context, examples, f"看到“{words}”等词语时，读 {py}；其他搭配结合词义判断。"

    return (
        "罕见、古语或词典保留读音，本册没有可用词例。",
        [],
        f"本册通常不读 {py}；遇到生僻词时查词典确认。",
    )


def build(data: dict, words_per_reading: int = 3) -> dict:
    """构建可直接 JSON 序列化的多音字文档。"""
    chars = _all_chars(data)
    all_readings: dict[str, list[str]] = {}
    for ch in chars:
        values = _unique(pinyin(ch, style=Style.TONE, heteronym=True, strict=True)[0])
        if len(values) > 1:
            all_readings[ch] = values

    book_readings, book_words = _book_readings_and_words(data)
    reading_sets = {ch: set(values) for ch, values in all_readings.items()}
    word_examples = _dictionary_words(
        set(all_readings), reading_sets, book_words
    )

    rows = []
    for ch in chars:
        if ch not in all_readings:
            continue
        appeared = book_readings.get(ch, set())
        groups: dict[str, list[dict]] = {
            "本册出现": [],
            "常用": [],
            "不常用": [],
        }

        for py in all_readings[ch]:
            all_examples = word_examples.get((ch, py), [])
            examples = all_examples[:words_per_reading] if words_per_reading else all_examples
            if py in appeared:
                group = "本册出现"
            elif all_examples:
                group = "常用"
            else:
                group = "不常用"
            context, selected_examples, quick_rule = _guidance(ch, py, group, examples)
            entry = {
                "读音": py,
                "语境": context,
                "例子": selected_examples,
                "快速判断": quick_rule,
                "_候选词数量": len(all_examples),
            }
            groups[group].append(entry)

        # Python 排序稳定；数量相同时保留读音在词典中的原始顺序。
        for entries in groups.values():
            entries.sort(key=lambda entry: entry["_候选词数量"], reverse=True)
            for entry in entries:
                del entry["_候选词数量"]
        rows.append({"字": ch, **groups})

    reading_count = sum(
        len(row[group])
        for row in rows
        for group in ("本册出现", "常用", "不常用")
    )

    return {
        "说明": (
            "收录源文件中出现、且 pypinyin 单字词典提供两个或以上读音的汉字；"
            "按 struct.json 的逐字注音区分读音是否在本册出现。每个读音整理为"
            "语境、例子和快速判断；特殊语法字使用人工规则，其余根据本册及词典"
            "词例生成，罕见读音明确提示查词典确认。"
        ),
        "多音字数量": len(rows),
        "读音数量": reading_count,
        "多音字": rows,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="从 struct.json 提取多音字及组词")
    parser.add_argument("input", type=Path, help="输入的 struct.json")
    parser.add_argument("-o", "--out", type=Path, help="输出 JSON，默认打印到 stdout")
    parser.add_argument(
        "--words-per-reading",
        type=int,
        default=3,
        help="每个读音最多保留几个词（默认 3；0 表示不限制）",
    )
    args = parser.parse_args(argv)

    if args.words_per_reading < 0:
        parser.error("--words-per-reading 不能小于 0")
    if not args.input.is_file():
        parser.error(f"找不到输入文件：{args.input}")

    try:
        data = json.loads(args.input.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"读取失败：{error}", file=sys.stderr)
        return 1

    result = {"源文件": args.input.name, **build(data, args.words_per_reading)}
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text, encoding="utf-8")
        print(f"已写入 {args.out}（{result['多音字数量']} 个多音字）", file=sys.stderr)
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
