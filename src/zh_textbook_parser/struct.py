"""简化结构 struct.json：目录 + 课文 + 园地 + 附录，正文逐字注音。

课本已有注音的字直接采用原读音（多音字以它为准），没有注音的字用 pypinyin
按词组推断补全。拼音串与正文按「字」一一对应，用空格分隔，非汉字原样保留。
"""

from __future__ import annotations

import logging
import warnings

with warnings.catch_warnings():  # jieba 在 3.12 下的正则转义告警
    warnings.simplefilter("ignore", SyntaxWarning)
    import jieba

from pypinyin import Style, load_phrases_dict, pinyin

from .appendix import RADICAL_TABLE

jieba.setLogLevel(logging.ERROR)

# 课本里的古诗文，pypinyin 词典没收、单字默认读音又不对的地方
PHRASE_FIX = {
    "似剪刀": [["sì"], ["jiǎn"], ["dāo"]],
    "一行白鹭": [["yī"], ["háng"], ["bái"], ["lù"]],
    "子鼠": [["zǐ"], ["shǔ"]],
    "万颗子": [["wàn"], ["kē"], ["zǐ"]],
    "管子": [["guǎn"], ["zǐ"]],
}

# 经多音字表逐项结合上下文审核后的修正。它们是明确的数据校对结果，最后覆盖
# 自动推断和 PDF 提取值；不要把未经审核的词库候选加入这里。
REVIEWED_PHRASE_FIX = {
    "着急": [["zháo"], ["jí"]],
    "不要": [["bú"], ["yào"]],
    "转动": [["zhuàn"], ["dòng"]],
    "扑棱棱": [["pū"], ["lēng"], ["lēng"]],
    "结结实实": [["jiē"], ["jiē"], ["shí"], ["shí"]],
    "高兴地说": [["gāo"], ["xìng"], ["de"], ["shuō"]],
    "一次": [["yí"], ["cì"]],
}

load_phrases_dict({**PHRASE_FIX, **REVIEWED_PHRASE_FIX})
for _phrase in (*PHRASE_FIX, *REVIEWED_PHRASE_FIX):
    jieba.add_word(_phrase)  # 别被分词切散，否则词组读音用不上


def _is_han(ch: str) -> bool:
    return "一" <= ch <= "鿿"


def annotate(text: str, known: dict[int, str] | None = None) -> str:
    """给整段文字注音。

    返回空格分隔的拼音串，`拼音.split(" ")` 与 `全文` 逐字一一对应：标点保留
    原样，空白对应空串。汉字按整段送进 pypinyin，好让它按词组判多音字。
    known 中的课本原注音最后覆盖推断结果，因此只补没有原注音的位置。
    """
    if not text:
        return ""
    out: list[str] = []
    buf: list[str] = []

    def flush() -> None:
        if not buf:
            return
        # 先分词再注音：pypinyin 自带的简单切分会把「去年长颈鹿」切成「年长」
        for word in jieba.lcut("".join(buf)):
            out.extend(item[0] for item in pinyin(word, style=Style.TONE))
        buf.clear()

    for ch in text:
        if _is_han(ch):
            buf.append(ch)
        else:
            flush()
            out.append("" if ch.isspace() else ch)
    flush()

    if len(out) != len(text):  # 兜底：逐字来一遍
        out = [
            pinyin(ch, style=Style.TONE)[0][0] if _is_han(ch) else ("" if ch.isspace() else ch)
            for ch in text
        ]
    for i, py in (known or {}).items():
        if 0 <= i < len(out):
            out[i] = py

    # 仅应用已经逐项人工批准的完整短语；同一短语出现多次时全部修正。
    for phrase, values in REVIEWED_PHRASE_FIX.items():
        start = text.find(phrase)
        while start >= 0:
            for offset, value in enumerate(values):
                out[start + offset] = value[0]
            start = text.find(phrase, start + 1)
    return " ".join(out)


def _lesson_text(lesson: dict) -> tuple[str, str]:
    parts: list[str] = []
    known: dict[int, str] = {}
    pos = 0
    for unit in lesson["正文"]:
        for z in unit["注音"]:
            if "序" in z:
                known[pos + z["序"]] = z["拼音"]
        parts.append(unit["文本"])
        pos += len(unit["文本"])
    text = "".join(parts)
    return text, annotate(text, known)


def _section_text(section: dict) -> tuple[str, str]:
    source_notes = list(section.get("生字", []))
    parts: list[tuple[str, list[dict]]] = [
        (item["文本"], item["注音"]) for item in section["条目"]
    ]
    picked = section.get("选文")
    if picked:
        head = "".join(x for x in (picked["标题"], picked["作者"]) if x)
        parts.append((head, []))
        parts += [(unit["文本"], unit["注音"]) for unit in picked["正文"]]
    continuation = section.get("续排", [])
    parts += [(item["文本"], item["注音"]) for item in continuation]
    parts = [(part, notes) for part, notes in parts if part]
    text = " ".join(part for part, _ in parts)

    # 通常同一栏目里同一个字沿用同一份原书注音。匹配题是例外：PDF 用同一个
    # 占位字承载 fēng/chǎo/mù 等不同提示音，必须按出现位置覆盖。
    all_notes = source_notes + [note for _, notes in parts for note in notes]
    variants: dict[str, set[str]] = {}
    global_known: dict[str, str] = {}
    for note in all_notes:
        global_known[note["字"]] = note["拼音"]
        variants.setdefault(note["字"], set()).add(note["拼音"])
    conflicts = {char for char, readings in variants.items() if len(readings) > 1}
    by_index = {
        i: global_known[c]
        for i, c in enumerate(text)
        if c in global_known and c not in conflicts
    }

    offset = 0
    for part, notes in parts:
        cursor = -1
        for note in notes:
            index = note.get("序")
            if index is None:
                index = part.find(note["字"], cursor + 1)
            if index >= 0 and note["字"] in conflicts:
                by_index[offset + index] = note["拼音"]
                cursor = index
        offset += len(part) + 1  # 各条目之间的一个空格
    return text, annotate(text, by_index)


def _appendix_rows(table: dict) -> list[dict]:
    rows: list[dict] = []
    for group in table["分组"]:
        for row in group["行"]:
            item = {
                "模块": table["名称"],
                "分组": group["名称"],
                "序号": row["标签"],
                "字": [],
                "词": [],
                "拼音": [],
            }
            content = row["内容"]
            if table["名称"] == RADICAL_TABLE:
                item["序号"] = content[0]
                item["词"] = content[1:]
                item["拼音"] = [annotate(value) for value in content[1:]]
            elif content and isinstance(content[0], dict):  # 识字表：自带注音
                item["字"] = [c["字"] for c in content]
                item["拼音"] = [c["拼音"] or annotate(c["字"]) for c in content]
            elif table["名称"] == "词语表":
                item["词"] = content
                item["拼音"] = [annotate(w) for w in content]
            else:
                item["字"] = content
                item["拼音"] = [annotate(c) for c in content]
            rows.append(item)
    return rows


def build(data: dict) -> dict:
    """把完整解析结果压成 struct.json。"""
    lessons: list[dict] = []
    for lesson in data.get("课文", []):
        text, py = _lesson_text(lesson)
        lessons.append(
            {
                "单元": (lesson.get("单元") or {}).get("单元"),
                "课号": lesson["课号"],
                "栏目": lesson["栏目"],
                "课题": lesson["课题"],
                "标题": lesson["标题"],
                "作者": lesson["作者"],
                "年代": lesson["年代"] or lesson["国别"],
                "页码": lesson["页码"],
                "全文": text,
                "拼音": py,
            }
        )

    gardens: list[dict] = []
    for garden in data.get("语文园地", []):
        sections = []
        for section in garden["栏目"]:
            text, py = _section_text(section)
            sections.append({"名称": section["名称"], "全文": text, "拼音": py})
        gardens.append(
            {
                "单元": (garden.get("单元") or {}).get("单元"),
                "标题": garden["标题"],
                "页码": garden["页码"],
                "栏目": sections,
            }
        )

    appendix: list[dict] = []
    for table in data.get("附录", []):
        appendix += _appendix_rows(table)

    catalog = (
        [
            {
                "类型": "课文",
                "单元": x["单元"],
                "课号": x["课号"],
                "标题": x["标题"],
                "页码": x["页码"],
            }
            for x in lessons
        ]
        + [
            {"类型": "园地", "单元": x["单元"], "标题": x["标题"], "页码": x["页码"]}
            for x in gardens
        ]
        + [
            {"类型": "附录", "标题": t["名称"], "页码": t["页码"]}
            for t in data.get("附录", [])
        ]
    )

    return {
        "文件": data.get("文件"),
        "目录": catalog,
        "课文": lessons,
        "园地": gardens,
        "附录": appendix,
    }
