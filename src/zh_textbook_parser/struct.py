"""简化结构 struct.json：目录 + 课文 + 园地 + 附录，正文逐字注音。

课本已有注音的字直接采用原读音（多音字以它为准），没有注音的字用 pypinyin
按词组推断补全。拼音串与正文按「字」一一对应，用空格分隔，非汉字原样保留。
"""

from __future__ import annotations

import logging
import re
import warnings

with warnings.catch_warnings():  # jieba 在 3.12 下的正则转义告警
    warnings.simplefilter("ignore", SyntaxWarning)
    import jieba

from pypinyin import Style, load_phrases_dict, pinyin

from .appendix import COLUMN_TABLES

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
    "一起来": [["yì"], ["qǐ"], ["lái"]],
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
    read_aloud_title = False
    for unit in lesson["正文"]:
        unit_text = unit["文本"]
        if unit_text == "读一读。" and parts:
            parts.append(" ")
            pos += 1
        for z in unit["注音"]:
            if "序" in z:
                known[pos + z["序"]] = z["拼音"]
        parts.append(unit_text)
        pos += len(unit_text)
        if unit_text == "读一读。" or read_aloud_title:
            parts.append(" ")
            pos += 1
            read_aloud_title = unit_text == "读一读。"
    text = "".join(parts)
    title = lesson.get("标题") or ""
    if title == "交朋友":
        crossed = (
            "我也喜欢。放学后我喜欢跳绳。你呢？"
            "我们一起去跳绳吧！好啊！"
        )
        dialogue = (
            "我喜欢跳绳。你呢？我也喜欢。"
            "放学后我们一起去跳绳吧！好啊！"
        )
        start = text.find(crossed)
        if start >= 0:
            text = text[:start] + dialogue + text[start + len(crossed) :]
            for index in range(start, start + len(dialogue)):
                known.pop(index, None)
    if (
        title
        and not any(_is_han(char) for char in title)
        and any(char.isalpha() for char in title)
    ):
        # 拼音课常先排声韵母练习、再排汉字词语。PDF 中二者靠版面分区，纯
        # 文本拼接后会挤成同一行；在文字系统切换处补一个结构换行空格。
        separated: list[str] = []
        shifted: dict[int, str] = {}
        previous = ""
        for old_index, char in enumerate(text):
            latin = char.isalpha() and not _is_han(char)
            previous_latin = previous.isalpha() and not _is_han(previous)
            if previous and ((latin and _is_han(previous)) or (_is_han(char) and previous_latin)):
                separated.append(" ")
            new_index = len(separated)
            separated.append(char)
            if old_index in known:
                shifted[new_index] = known[old_index]
            previous = char
        text = "".join(separated)
        known = shifted
    return text, annotate(text, known)


def _selection_parts(units: list[dict]) -> list[tuple[str, list[dict]]]:
    """园地选文按原书基线组行，避免逗号断句把同一诗行拆开。"""
    rows: list[tuple[str, list[dict], float]] = []
    for unit in units:
        text = unit["文本"]
        notes = [dict(note) for note in unit["注音"]]
        y = unit["bbox"][1]
        if rows and abs(rows[-1][2] - y) < 2:
            old_text, old_notes, old_y = rows[-1]
            offset = len(old_text)
            for note in notes:
                if "序" in note:
                    note["序"] += offset
            rows[-1] = (old_text + text, old_notes + notes, old_y)
        else:
            rows.append((text, notes, y))
    return [(text, notes) for text, notes, _ in rows]


def _practice_parts(items: list[dict]) -> list[tuple[str, list[dict]]]:
    """“用拼音”按原 PDF 基线合并分段，组内窄空格不触发查看器换行。"""
    rows: list[tuple[str, list[dict], float]] = []
    for item in items:
        original = item["文本"]
        replacement = "" if any(_is_han(char) for char in original) else "\u2005"
        text = original.replace(" ", replacement)
        notes = [dict(note) for note in item["注音"]]
        for note in notes:
            if "序" in note:
                note["序"] = len(original[: note["序"]].replace(" ", replacement))
        y = item["bbox"][1]
        if rows and abs(rows[-1][2] - y) < 2:
            old_text, old_notes, old_y = rows[-1]
            offset = len(old_text) + 1
            for note in notes:
                if "序" in note:
                    note["序"] += offset
            rows[-1] = (old_text + "\u2005" + text, old_notes + notes, old_y)
        else:
            rows.append((text, notes, y))
    return [(text, notes) for text, notes, _ in rows]


def _compact_part(item: dict, replacement: str = "") -> tuple[str, list[dict]]:
    original = item["文本"]
    notes = [dict(note) for note in item["注音"]]
    for note in notes:
        if "序" in note:
            note["序"] = len(original[: note["序"]].replace(" ", replacement))
    return original.replace(" ", replacement), notes


def _matching_practice_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """重排“读一读，连一连”：三组字母匹配和右侧提示气泡互不串行。"""
    if not items or items[0]["文本"].replace(" ", "") != "读一读，连一连。":
        return None
    prompt = _compact_part(items[0])
    left = [item for item in items[1:] if item["bbox"][0] < 200]
    targets = [
        item
        for item in items[1:]
        if 250 < item["bbox"][0] < 310 and len(item["文本"].strip()) == 1
    ]
    bubble = [item for item in items[1:] if item["bbox"][0] >= 310]
    if len(left) != 3 or len(targets) != 3 or not bubble:
        return None

    parts = [prompt]
    for source in sorted(left, key=lambda item: item["bbox"][1]):
        center = (source["bbox"][1] + source["bbox"][3]) / 2
        target = min(
            targets,
            key=lambda item: abs((item["bbox"][1] + item["bbox"][3]) / 2 - center),
        )
        source_text, source_notes = _compact_part(source, "\u2005")
        target_text, target_notes = _compact_part(target)
        offset = len(source_text) + 1
        for note in target_notes:
            if "序" in note:
                note["序"] += offset
        parts.append((source_text + "　" + target_text, source_notes + target_notes))
        targets.remove(target)

    bubble_text = "".join(_compact_part(item)[0] for item in bubble)
    bubble_notes: list[dict] = []
    offset = 0
    for item in bubble:
        text, notes = _compact_part(item)
        for note in notes:
            if "序" in note:
                note["序"] += offset
        bubble_notes.extend(notes)
        offset += len(text)
    parts.append((bubble_text, bubble_notes))
    return parts


def _picture_finding_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """重排“在图里找一找”：按 PDF 基线保留三行词语，避免逐字竖排。"""
    if not items or items[0]["文本"].replace(" ", "") != "读一读，在图里找一找。":
        return None

    parts = [_compact_part(items[0])]
    rows: list[list[dict]] = []
    for item in sorted(items[1:], key=lambda value: (value["bbox"][1], value["bbox"][0])):
        center = (item["bbox"][1] + item["bbox"][3]) / 2
        if rows:
            previous = sum(
                (cell["bbox"][1] + cell["bbox"][3]) / 2 for cell in rows[-1]
            ) / len(rows[-1])
        else:
            previous = -100
        if not rows or abs(center - previous) > 3:
            rows.append([])
        rows[-1].append(item)

    for row in rows:
        row_text = ""
        row_notes: list[dict] = []
        for item in sorted(row, key=lambda value: value["bbox"][0]):
            text, notes = _compact_part(item, "\u3000")
            offset = len(row_text) + (1 if row_text else 0)
            for note in notes:
                if "序" in note:
                    note["序"] += offset
            if row_text:
                row_text += "\u3000"
            row_text += text
            row_notes.extend(notes)
        parts.append((row_text, row_notes))
    return parts


def _word_expansion_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """重排园地四“车”的词语扩展，并恢复田字格中的四组词。"""
    if not items or items[0]["文本"].replace(" ", "") != "读一读，说一说。":
        return None
    by_text = {item["文本"].replace(" ", ""): item for item in items}
    groups = [
        ["车"],
        ["火车", "马车", "汽车"],
        ["上车", "坐车", "车站", "车厢"],
    ]
    required = {word for group in groups for word in group}
    if not required.issubset(by_text) or "拼一拼，写一写。" not in by_text:
        return None

    parts = [_compact_part(items[0])]
    for group in groups:
        row_text = ""
        row_notes: list[dict] = []
        for word in group:
            text, notes = _compact_part(by_text[word])
            offset = len(row_text) + (1 if row_text else 0)
            for note in notes:
                if "序" in note:
                    note["序"] += offset
            if row_text:
                row_text += "\u3000"
            row_text += text
            row_notes.extend(notes)
        parts.append((row_text, row_notes))

    parts.append(_compact_part(by_text["拼一拼，写一写。"]))
    parts.append(
        (
            "门口　生日　题目　田野",
            [
                {"字": "门", "拼音": "mén", "序": 0},
                {"字": "口", "拼音": "kǒu", "序": 1},
                {"字": "生", "拼音": "shēng", "序": 3},
                {"字": "日", "拼音": "rì", "序": 4},
                {"字": "题", "拼音": "tí", "序": 6},
                {"字": "目", "拼音": "mù", "序": 7},
                {"字": "田", "拼音": "tián", "序": 9},
                {"字": "野", "拼音": "yě", "序": 10},
            ],
        )
    )
    return parts


def _season_word_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """园地五四季词语按原书分行，并保留下一页合并进来的后续练习。"""
    by_text = {item["文本"].replace(" ", ""): item for item in items}
    rows = [
        ["春天", "夏天", "秋天", "冬天"],
        ["大地", "树叶", "青草", "莲花"],
        ["飞鸟", "小鱼", "青蛙", "雪人"],
    ]
    required = {word for row in rows for word in row}
    required.update(
        {"读一读，说一说。", "我最喜欢冬天，因为", "冬天可以堆雪人……"}
    )
    if not required.issubset(by_text):
        return None

    prompt = by_text["读一读，说一说。"]
    consumed = {id(prompt)}
    parts = [_compact_part(prompt)]
    for row in rows:
        parts.append(("　".join(row), []))
        consumed.update(id(by_text[word]) for word in row)

    bubble_start = by_text["我最喜欢冬天，因为"]
    bubble_end = by_text["冬天可以堆雪人……"]
    consumed.update((id(bubble_start), id(bubble_end)))
    parts.append(("我最喜欢冬天，因为冬天可以堆雪人……", []))

    continuation = [
        "你认识哪些同学的名字？是怎么认识的？",
        "和同学交流。",
        "这些卡片上的名字我都认识。",
        "我从写字本上认识了一些同学的名字。",
        "一年级（3）班　刘丽",
        "李晓宇　6岁",
    ]
    continuation_sources = [
        ["你认识哪些同学的名字？是怎么认识的？"],
        ["和同学交流。"],
        ["这些卡片上的", "名字我都认识。"],
        ["我从写字本上认识", "了一些同学的名字。"],
        ["一年级（3）班", "刘丽"],
        ["李晓宇", "6岁"],
    ]
    for text, source_texts in zip(continuation, continuation_sources):
        source_items = [by_text[value] for value in source_texts if value in by_text]
        if len(source_items) != len(source_texts):
            continue
        notes: list[dict] = []
        offset = 0
        for item in source_items:
            compact, item_notes = _compact_part(item)
            for note in item_notes:
                if "序" in note:
                    note["序"] += offset
            notes.extend(item_notes)
            offset += len(compact)
            consumed.add(id(item))
        parts.append((text, notes))

    parts.extend(
        (item["文本"], item["注音"]) for item in items if id(item) not in consumed
    )
    return parts


def _pronunciation_word_parts(
    items: list[dict],
) -> list[tuple[str, list[dict]]] | None:
    """园地六字音练习跨页排版，并恢复被识字条过滤的八组词。"""
    by_text = {item["文本"].replace(" ", ""): item for item in items}
    required = {
        "读一读，读准字音。",
        "读一读，和同学交流你的发现。",
        "树林桃桥",
        "花草莲菜",
        "你在路上认识了哪些字？和同学交流。",
        "看图写词语，再说一两句话。",
    }
    if not required.issubset(by_text):
        return None

    parts = [_compact_part(by_text["读一读，读准字音。"])]
    parts.extend(
        [
            ("你们　家里　男生　蓝色", []),
            ("上山　三年　写字　报纸", []),
            _compact_part(by_text["读一读，和同学交流你的发现。"]),
            ("树　林　桃　桥", []),
            ("花　草　莲　菜", []),
            ("很多木字旁的字都和树木有关。", []),
            ("“桥”字为什么和树木有关呢？我想问问老师。", []),
            _compact_part(by_text["你在路上认识了哪些字？和同学交流。"]),
            _compact_part(by_text["看图写词语，再说一两句话。"]),
        ]
    )
    return parts


def _comparison_word_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """园地七跨页字词练习分行，并恢复田字格中被过滤的八个字。"""
    by_text = {item["文本"].replace(" ", ""): item for item in items}
    required = {
        "比一比，写一写。",
        "读一读，和同学交流你的发现。",
        "明晚昨春",
        "妈奶姐妹",
        "读一读，背一背。",
        "早晨起来，面向太阳。",
        "前面是东，后面是西。",
        "左面是北，右面是南。",
    }
    if not required.issubset(by_text):
        return None

    return [
        _compact_part(by_text["比一比，写一写。"]),
        ("了　才　云　山", []),
        ("儿　四　我　心", []),
        _compact_part(by_text["读一读，和同学交流你的发现。"]),
        ("明　晚　昨　春", []),
        ("妈　奶　姐　妹", []),
        ("这几个字的意思都和时间有关。", []),
        _compact_part(by_text["读一读，背一背。"]),
        _compact_part(by_text["早晨起来，面向太阳。"]),
        _compact_part(by_text["前面是东，后面是西。"]),
        _compact_part(by_text["左面是北，右面是南。"]),
    ]


def _paired_word_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """园地八成对词语按两行排列，并保留下一页的新年祝福提示。"""
    by_text = {item["文本"].replace(" ", ""): item for item in items}
    required = {
        "读一读。",
        "果皮树皮",
        "加法办法",
        "回来回答",
        "许多不许",
        "到处四处",
        "方向地方",
        "新年快到了，给家人或朋友写一句祝福的话吧！",
    }
    if not required.issubset(by_text):
        return None
    return [
        _compact_part(by_text["读一读。"]),
        ("果皮　树皮　加法　办法　回来　回答", []),
        ("许多　不许　到处　四处　方向　地方", []),
        _compact_part(by_text["新年快到了，给家人或朋友写一句祝福的话吧！"]),
    ]


def _garden_eight_writing_parts(
    items: list[dict],
) -> list[tuple[str, list[dict]]] | None:
    """园地八书写提示按规则与示例字分组，去除描红重复字。"""
    texts = {item["文本"].replace(" ", "") for item in items}
    required = {
        "先外后内。笔顺规则：",
        "笔顺规则：",
        "小小小＿＿先中间后两边。",
    }
    if not required.issubset(texts):
        return None
    return [
        ("笔顺规则：先外后内。", []),
        ("月　风", []),
        ("笔顺规则：先中间后两边。", []),
        ("小　水", []),
    ]


TIME_WORDS = {
    "上午",
    "下午",
    "晚上",
    "昨天",
    "今天",
    "明天",
    "上个月",
    "这个月",
    "下个月",
    "去年",
    "今年",
    "明年",
}


def _time_word_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """园地四时间词按原书基线排成三行，并忽略下方书写练习残片。"""
    words = [item for item in items if item["文本"].replace(" ", "") in TIME_WORDS]
    if len(words) != len(TIME_WORDS):
        return None

    rows: list[list[dict]] = []
    for item in sorted(words, key=lambda value: (value["bbox"][1], value["bbox"][0])):
        center = (item["bbox"][1] + item["bbox"][3]) / 2
        if rows:
            previous = sum(
                (cell["bbox"][1] + cell["bbox"][3]) / 2 for cell in rows[-1]
            ) / len(rows[-1])
        else:
            previous = -100
        if not rows or abs(center - previous) > 3:
            rows.append([])
        rows[-1].append(item)
    if len(rows) != 3 or any(len(row) != 4 for row in rows):
        return None

    parts: list[tuple[str, list[dict]]] = []
    for row in rows:
        row_text = ""
        row_notes: list[dict] = []
        for item in sorted(row, key=lambda value: value["bbox"][0]):
            text, notes = _compact_part(item)
            offset = len(row_text) + (1 if row_text else 0)
            for note in notes:
                if "序" in note:
                    note["序"] += offset
            if row_text:
                row_text += "\u3000"
            row_text += text
            row_notes.extend(notes)
        parts.append((row_text, row_notes))
    return parts


def _opposite_word_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """园地五反义词按两行三组排列，并恢复被识字条过滤的第二行。"""
    texts = {item["文本"].replace(" ", "") for item in items}
    if not {"南", "北", "男", "女", "开", "关"}.issubset(texts):
        return None
    if not {"我也会说这样", "的词语……"}.issubset(texts):
        return None
    return [
        ("南—北　男—女　开—关", []),
        ("正—反　先—后　内—外", []),
        ("我也会说这样的词语……", []),
    ]


def _character_structure_parts(
    items: list[dict],
) -> list[tuple[str, list[dict]]] | None:
    """园地八字形结构连线题分排，并纠正篮子中误识别的“田”。"""
    texts = {item["文本"].replace(" ", "") for item in items}
    required = {
        "连一连。",
        "牛",
        "羊",
        "只",
        "爪",
        "叶",
        "花",
        "口",
        "作",
        "元",
        "拼",
        "音",
        "巴",
        "白",
        "有些字可以",
        "分成上下两部分。",
    }
    if not required.issubset(texts):
        return None
    prompt = next(item for item in items if item["文本"].replace(" ", "") == "连一连。")
    return [
        _compact_part(prompt),
        ("牛　羊　只　爪　叶", []),
        ("花　田　作", []),
        ("元　拼　音　巴　白", []),
        ("有些字可以分成上下两部分。", []),
    ]


COURSE_NAMES = (
    "综合实践活动",
    "道德与法治",
    "体育与健康",
    "语文",
    "数学",
    "美术",
    "科学",
    "音乐",
    "写字",
    "班会",
    "劳动",
)


def _course_cells(text: str) -> list[str]:
    compact = text.replace(" ", "").replace("＿", "")
    compact = compact.removeprefix("上午").removeprefix("下").removeprefix("午")
    cells: list[str] = []
    match = re.match(r"第[一二三四五六]节", compact)
    if match:
        cells.append(match.group())
        compact = compact[match.end() :]
    while compact:
        course = next((name for name in COURSE_NAMES if compact.startswith(name)), None)
        if course is None:
            cells.append(compact)
            break
        cells.append(course)
        compact = compact[len(course) :]
    return cells


def _schedule_parts(items: list[dict]) -> list[tuple[str, list[dict]]] | None:
    """课程表按基线组行，并把 PDF 合并的相邻课程名重新拆开。"""
    if not items or not any("课程表" in item["文本"] for item in items):
        return None
    weekdays = [
        item
        for item in items
        if re.fullmatch(r"星期[一二三四五]", item["文本"].replace(" ", ""))
    ]
    if len(weekdays) < 5:
        return None

    parts: list[tuple[str, list[dict]]] = [
        ("看看你的课程表，星期三有什么课？", []),
        ("课程表", []),
        ("　".join(item["文本"].replace(" ", "") for item in weekdays), []),
    ]
    table = [item for item in items if item["bbox"][1] > weekdays[-1]["bbox"][1] + 8]
    rows: list[list[dict]] = []
    for item in table:
        center = (item["bbox"][1] + item["bbox"][3]) / 2
        if rows:
            previous = sum(
                (cell["bbox"][1] + cell["bbox"][3]) / 2 for cell in rows[-1]
            ) / len(rows[-1])
        else:
            previous = -100
        if not rows or abs(center - previous) > 9:
            rows.append([])
        rows[-1].append(item)

    for row in rows:
        cells: list[str] = []
        for item in sorted(row, key=lambda value: value["bbox"][0]):
            if item["文本"].replace(" ", "") == "上午":
                continue
            cells.extend(_course_cells(item["文本"]))
        if cells:
            parts.append(("　".join(cells), []))
    return parts


def _section_text(section: dict) -> tuple[str, str]:
    source_notes = list(section.get("生字", []))
    schedule = (
        _schedule_parts(section["条目"])
        if section.get("名称") == "识字加油站"
        else None
    )
    time_words = (
        _time_word_parts(section["条目"])
        if section.get("名称") == "识字加油站"
        else None
    )
    opposite_words = (
        _opposite_word_parts(section["条目"])
        if section.get("名称") == "识字加油站"
        else None
    )
    character_structures = (
        _character_structure_parts(section["条目"])
        if section.get("名称") == "识字加油站"
        else None
    )
    matching = (
        _matching_practice_parts(section["条目"])
        if section.get("名称") == "字词句运用"
        else None
    )
    picture_finding = (
        _picture_finding_parts(section["条目"])
        if section.get("名称") == "字词句运用"
        else None
    )
    word_expansion = (
        _word_expansion_parts(section["条目"])
        if section.get("名称") == "字词句运用"
        else None
    )
    season_words = (
        _season_word_parts(section["条目"])
        if section.get("名称") == "字词句运用"
        else None
    )
    pronunciation_words = (
        _pronunciation_word_parts(section["条目"])
        if section.get("名称") == "字词句运用"
        else None
    )
    comparison_words = (
        _comparison_word_parts(section["条目"])
        if section.get("名称") == "字词句运用"
        else None
    )
    paired_words = (
        _paired_word_parts(section["条目"])
        if section.get("名称") == "字词句运用"
        else None
    )
    writing_parts = (
        _garden_eight_writing_parts(section["条目"])
        if section.get("名称") == "书写提示"
        else None
    )
    parts: list[tuple[str, list[dict]]] = schedule or time_words or opposite_words or character_structures or matching or picture_finding or word_expansion or season_words or pronunciation_words or comparison_words or paired_words or writing_parts or (
        _practice_parts(section["条目"])
        if section.get("名称") == "用拼音"
        else [(item["文本"], item["注音"]) for item in section["条目"]]
    )
    picked = section.get("选文")
    if picked:
        head = "".join(x for x in (picked["标题"], picked["作者"]) if x)
        parts.append((head, []))
        parts += _selection_parts(picked["正文"])
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
            if table["名称"] in COLUMN_TABLES:
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
                "出处": lesson.get("出处"),
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
