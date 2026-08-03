"""简化结构 struct.json：目录 + 课文 + 园地 + 附录，正文逐字注音。

课本只给生字注音，这里把整篇补全：课本标注过的字用课本的读音（多音字以它
为准），其余用 pypinyin 按词组推断。拼音串与正文按「字」一一对应，用空格
分隔，非汉字原样保留。
"""

from __future__ import annotations

import logging
import warnings

with warnings.catch_warnings():  # jieba 在 3.12 下的正则转义告警
    warnings.simplefilter("ignore", SyntaxWarning)
    import jieba

from pypinyin import Style, load_phrases_dict, pinyin

jieba.setLogLevel(logging.ERROR)

# 课本里的古诗文，pypinyin 词典没收、单字默认读音又不对的地方
PHRASE_FIX = {
    "似剪刀": [["sì"], ["jiǎn"], ["dāo"]],
    "一行白鹭": [["yī"], ["háng"], ["bái"], ["lù"]],
    "子鼠": [["zǐ"], ["shǔ"]],
    "万颗子": [["wàn"], ["kē"], ["zǐ"]],
    "管子": [["guǎn"], ["zǐ"]],
}
load_phrases_dict(PHRASE_FIX)
for _phrase in PHRASE_FIX:
    jieba.add_word(_phrase)  # 别被分词切散，否则词组读音用不上


def _is_han(ch: str) -> bool:
    return "一" <= ch <= "鿿"


def annotate(text: str, known: dict[int, str] | None = None) -> str:
    """给整段文字注音。

    返回空格分隔的拼音串，`拼音.split(" ")` 与 `全文` 逐字一一对应：标点保留
    原样，空白对应空串。汉字按整段送进 pypinyin，好让它按词组判多音字。
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
    known: dict[str, str] = {z["字"]: z["拼音"] for z in section.get("生字", [])}
    parts = [item["文本"] for item in section["条目"]]
    for item in section["条目"]:
        known.update({z["字"]: z["拼音"] for z in item["注音"]})
    picked = section.get("选文")
    if picked:
        head = "".join(x for x in (picked["标题"], picked["作者"]) if x)
        parts.append(head)
        parts += [u["文本"] for u in picked["正文"]]
        for u in picked["正文"]:
            known.update({z["字"]: z["拼音"] for z in u["注音"]})
    text = " ".join(p for p in parts if p)
    by_index = {i: known[c] for i, c in enumerate(text) if c in known}
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
            if content and isinstance(content[0], dict):  # 识字表：自带注音
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
