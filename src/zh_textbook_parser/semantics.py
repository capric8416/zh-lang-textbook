"""语义单元抽取：课文（标题 / 作者 / 年代 / 正文列表）与课后。"""

from __future__ import annotations

import re
from collections import Counter

from . import attribution
from .blocks import Char, Line, Span, round_box, union

# 句子切分标点：切开后标点跟在前一句尾部（顿号不切，避免把并列词拆碎）
SPLIT_PUNCT = "。！？；，…"
SENTENCE_END = "。！？…"  # 句末点号，用来判断分段
CLOSING = "”’」』）》"
LATIN_FONTS = ("Futura", "CenturyGothic", "Times", "Arial")

AUTHOR_RE = re.compile(r"^[\[\［](?P<年代>[^\]\］]+)[\]\］]\s*(?P<作者>.+)$")
SOURCE_LINE_RE = re.compile(r"^(?:汉乐府|北朝民歌|南北朝民歌|民间歌谣|民间故事)$")
NOTE_RE = re.compile(r"^[①-⑳]")
EX_MARK = "\t"  # 课后练习题的题号位（原文用制表符占位，前面是花朵项目符号图片）
BULLET = "◇"
SECTION_FONT = "FZHTK"  # 栏目标签用的黑体
INDENT_TOLERANCE = 4.0  # 段首缩进判定（pt）
READING_CORNER = "快乐读书吧"
MIXED_SECTION_LABELS = {"口语交际"}


def _is_latin_number(line: Line) -> bool:
    txt = line.text()
    return bool(re.fullmatch(r"\d{1,2}", txt)) and any(
        f.startswith(LATIN_FONTS) for f in line.fonts
    )


def dominant_size(lines: list[Line]) -> float:
    """正文主字号 —— 判断标题、注释都以它为基准。"""
    return _dominant_size(lines)


def _has_lesson_number(line: Line) -> bool:
    """这一行是否同时包含西文课号和中文课题。"""
    chars = line.visible_chars()
    return any(
        c.char.isdigit() and c.font.startswith(LATIN_FONTS) for c in chars
    ) and any(_is_cjk(c.char) for c in chars)


def lesson_dominant(lesson_lines: list[Line], page_body: list[Line]) -> float:
    """课文区的主字号。

    课文区字数够多就用它自己的（页脚的课后练习字号更小，会把正文挤成标题）；
    只剩标题和一两行小字时（识字表那种页面）退回整页的主字号。
    """
    numbered = [ln for ln in lesson_lines if _has_lesson_number(ln)]
    if numbered:
        # 有课号时可以先可靠剔除标题行，再忽略脚注/图片署名的小字。低年级
        # 识字课正文可能只有五六个大字，不能沿用普通课文的 20 字门槛。
        title_ids = {id(ln) for ln in numbered}
        prose = [
            ln for ln in lesson_lines if id(ln) not in title_ids and ln.size >= 13
        ]
        if sum(len(ln.visible_chars()) for ln in prose) >= 4:
            return _dominant_size(prose)
    chars = sum(len(ln.visible_chars()) for ln in lesson_lines)
    return _dominant_size(lesson_lines if chars >= 20 else page_body)


def _dominant_size(lines: list[Line]) -> float:
    weight: dict[float, int] = {}
    for ln in lines:
        for c in ln.visible_chars():
            weight[round(c.size, 1)] = weight.get(round(c.size, 1), 0) + 1
    return max(weight, key=lambda k: weight[k]) if weight else 0.0


def _chars_to_clauses(chars: list[tuple[Char, int]]) -> list[dict]:
    """按标点把整页字流切成句子单元。

    只在标点处断句：行尾没有标点的行会自然并入下一行（课本里正文常因插图
    绕排而在半句处换行）。连续标点（如 ……、！”）算一处，不重复断开。
    """
    units: list[dict] = []
    buf: list[tuple[Char, int]] = []
    for i, (c, para) in enumerate(chars):
        buf.append((c, para))
        if c.char in SPLIT_PUNCT:
            nxt = chars[i + 1][0].char if i + 1 < len(chars) else ""
            if nxt in SPLIT_PUNCT or nxt in CLOSING:
                continue
            units.append(_unit(buf, len(units) + 1))
            buf = []
    if buf and "".join(c.char for c, _ in buf).strip():
        units.append(_unit(buf, len(units) + 1))
    return units


def _unit(items: list[tuple[Char, int]], no: int) -> dict:
    chars = [c for c, _ in items]
    box = chars[0].bbox
    for c in chars[1:]:
        box = union(box, c.bbox)
    raw = "".join(c.char for c in chars)
    text = raw.strip()
    shift = len(raw) - len(raw.lstrip())
    zhuyin = [
        {"字": c.char, "拼音": c.pinyin, "序": i - shift}
        for i, c in enumerate(chars)
        if c.pinyin
    ]
    unit = {
        "序号": no,
        "段落": items[0][1],
        "文本": text,
        "字数": len(text),
        "注音": zhuyin,
        "bbox": round_box(box),
    }
    if text and text[-1] not in SPLIT_PUNCT + CLOSING + "、：":
        unit["跨页续句"] = True  # 这句在本页没写完，下一页接着
    return unit


def _ends_sentence(line: Line) -> bool:
    """行尾是否是句末点号（。！？…，可带收尾引号）。"""
    tail = [c.char for c in line.visible_chars()]
    while tail and tail[-1] in CLOSING:
        tail.pop()
    return bool(tail) and tail[-1] in SENTENCE_END


def _char_stream(lines: list[Line]) -> tuple[list[tuple[Char, int]], bool]:
    """按阅读顺序拼成字流，并给每个字标上段落号。

    只有「缩进 + 上一行以句末点号收尾」才算新段落：正文绕开插图排版时，
    续行的 x 起点也很靠右，不能只看缩进。
    """
    if not lines:
        return [], False
    left = min(ln.x0 for ln in lines)
    stream: list[tuple[Char, int]] = []
    para = 1
    first_indent = False
    for i, ln in enumerate(lines):
        indented = ln.x0 - left > ln.size * 0.5 + INDENT_TOLERANCE
        if i == 0:
            first_indent = indented
        elif indented and _ends_sentence(lines[i - 1]):
            para += 1
        stream.extend((c, para) for c in ln.visible_chars())
    return stream, first_indent


def is_reading_corner_page(body: list[Line]) -> bool:
    """页面是否为带独立主标题的「快乐读书吧」导读页。"""
    label = next((ln for ln in body if ln.text() == READING_CORNER), None)
    return bool(
        label
        and any(ln.y0 > label.y1 and ln.max_size >= 20 for ln in body)
    )


def _half_line(line: Line, midpoint: float, left: bool) -> Line | None:
    """按页面中线取一侧文字，保留每个字的原注音。"""
    chars = [c for c in line.visible_chars() if (c.cx < midpoint) == left]
    if not chars:
        return None
    spans = [Span(c.char, c.bbox, c.size, c.font) for c in chars]
    return Line(spans, chars)


def _bubble_stream(lines: list[Line], width: float) -> list[tuple[Char, int]]:
    """把左右云朵中的小字号文字聚成独立块，再按版面行序输出。"""
    midpoint = width / 2
    columns = [
        [part for line in lines if (part := _half_line(line, midpoint, left))]
        for left in (True, False)
    ]
    blocks: list[list[Line]] = []
    for column in columns:
        current: list[Line] = []
        for line in sorted(column, key=lambda item: item.y0):
            if current and line.y0 - current[-1].y1 >= line.size * 3:
                blocks.append(current)
                current = []
            current.append(line)
        if current:
            blocks.append(current)

    # 先按垂直重叠归成一排，再在同排内从左到右；云朵中的首行高度可能
    # 相差二三十点，不能直接对所有块按 y0 排序。
    rows: list[list[list[Line]]] = []
    for block in sorted(blocks, key=lambda item: min(line.y0 for line in item)):
        y0 = min(line.y0 for line in block)
        y1 = max(line.y1 for line in block)
        row = next(
            (
                item
                for item in rows
                if y0 <= max(line.y1 for part in item for line in part) + 10
                and y1 >= min(line.y0 for part in item for line in part) - 10
            ),
            None,
        )
        if row is None:
            row = []
            rows.append(row)
        row.append(block)

    stream: list[tuple[Char, int]] = []
    paragraph = 0
    for row in rows:
        for block in sorted(row, key=lambda item: min(line.x0 for line in item)):
            paragraph += 1
            for line in block:
                stream.extend((char, paragraph) for char in line.visible_chars())
    return stream


def extract_reading_corner(body: list[Line], width: float) -> dict | None:
    """抽取「快乐读书吧」内嵌书页，按左栏再右栏恢复阅读顺序。"""
    label = next((ln for ln in body if ln.text() == READING_CORNER), None)
    if label is None:
        return None

    title = max(
        (ln for ln in body if ln.y0 > label.y1),
        key=lambda ln: ln.max_size,
        default=None,
    )
    if title is None:
        return None

    book_starts = [
        ln.y0
        for ln in body
        if ln.y0 > title.y1 and ln.max_size >= 20 and ln.text() != title.text()
    ]
    if book_starts:
        book_y = min(book_starts)
        intro = [ln for ln in body if title.y1 < ln.y0 < book_y]
        book = [ln for ln in body if ln.y0 >= book_y]
        midpoint = width / 2
        left = [part for ln in book if (part := _half_line(ln, midpoint, True))]
        right = [part for ln in book if (part := _half_line(ln, midpoint, False))]
        content_lines = intro + left + right
    else:
        candidates = [ln for ln in body if ln.y0 > title.y1]
        main_size = dominant_size(candidates)
        content_lines = [ln for ln in candidates if abs(ln.size - main_size) < 0.6]
    if not book_starts and main_size <= 12:
        stream = _bubble_stream(content_lines, width)
        first_indent = False
    else:
        stream, first_indent = _char_stream(content_lines)

    return {
        "课号": None,
        "栏目": READING_CORNER,
        "课题": None,
        "标题": re.sub(r"\s+", "", title.text()),
        "标题注释号": None,
        "作者": None,
        "年代": None,
        "国别": None,
        "译者": None,
        "出处": None,
        "作者出处": None,
        "注释": [],
        "正文": _chars_to_clauses(stream),
        "首行缩进": first_indent,
    }


WRAP_MIN_CHARS = 8  # 只有够长的整行才可能是折行


def line_right_edge(lines: list[Line]) -> float:
    return max((ln.bbox[2] for ln in lines), default=0.0)


def is_wrapped(prev_line: Line, prev_text: str, line: Line, right_edge: float) -> bool:
    """line 是不是 prev_line 的折行续排。

    判据：上一行排到了右边界、够长、没有以句末点号收尾，两行字号一样且紧挨着。
    这样「湖心亭 / 露天剧场」这种按位置摆的词条不会被粘起来。
    """
    return (
        len(prev_text) >= WRAP_MIN_CHARS
        and prev_text[-1] not in SENTENCE_END + CLOSING
        and prev_line.bbox[2] >= right_edge - 12
        and abs(line.size - prev_line.size) < 1
        and 0 <= line.y0 - prev_line.y1 < prev_line.size * 1.2
    )


def merge_item(prev_item: dict, item: dict) -> None:
    offset = len(prev_item["文本"])
    prev_item["文本"] += item["文本"]
    for note in item["注音"]:
        note = dict(note)
        if "序" in note:
            note["序"] += offset
        prev_item["注音"].append(note)
    prev_item["bbox"] = round_box(union(tuple(prev_item["bbox"]), tuple(item["bbox"])))


def _is_cjk(ch: str) -> bool:
    return "一" <= ch <= "鿿"


def _is_exercise_line(line: Line) -> bool:
    """课后练习题：题号位是花朵图片 + 一个制表符占位。"""
    raw = "".join(s.text for s in line.spans)
    return raw.lstrip(" 　").startswith(EX_MARK)


def _is_read_aloud_label(line: Line) -> bool:
    return re.sub(r"\s+", "", line.text()) == "读一读。"


def _is_recognize_strip(line: Line) -> bool:
    """会认字条：逐字注音、纯汉字，并且字间明显疏排。

    一二年级课文的标题和正文也可能逐字注音，不能只凭「每个汉字都有
    拼音」判断。会认字条里的字彼此独立，间距约为字号的一半；正文的
    连续排版则紧得多。课号、标点或注释号也都说明这不是会认字条。
    """
    chars = line.visible_chars()
    if len(chars) < 4 or any(not _is_cjk(c.char) for c in chars):
        return False
    if not all(c.pinyin for c in chars):
        return False

    ordered = sorted(chars, key=lambda c: c.bbox[0])
    gaps = [
        right.bbox[0] - left.bbox[2]
        for left, right in zip(ordered, ordered[1:])
    ]
    min_size = min(c.size for c in ordered)
    return bool(gaps) and min(gaps) >= min_size * 0.35


def _continues_previous_line(previous: Line, line: Line) -> bool:
    """疏排行是否仍是绕图正文，而不是新起的会认字条。"""
    return (
        abs(line.size - previous.size) < 0.6
        and 0 <= line.y0 - previous.y1 < line.size * 1.5
        and not _ends_sentence(previous)
        and line.x0 <= previous.x0
    )


def recognize_strip_groups(lines: list[Line]) -> list[list[int]]:
    """返回真正的会认字条行组；连续多行视为同一组。

    插图旁的窄栏正文偶尔会让一整行汉字看起来像疏排字条。候选组只要和
    前一行或后一行存在续排关系，就仍属于正文，不能据此截断课文。
    """
    raw = [i for i, line in enumerate(lines) if _is_recognize_strip(line)]
    groups: list[list[int]] = []
    for index in raw:
        if groups and index == groups[-1][-1] + 1:
            groups[-1].append(index)
        else:
            groups.append([index])
    return [
        group
        for group in groups
        if not (
            (
                group[0] > 0
                and _continues_previous_line(lines[group[0] - 1], lines[group[0]])
            )
            or (
                group[-1] + 1 < len(lines)
                and _continues_previous_line(lines[group[-1]], lines[group[-1] + 1])
            )
        )
    ]


def _grid_chars(lines: list[Line]) -> list[Char]:
    """会写字表：田字格里的大字，黑字与红色描红字成对出现（同行同字、隔一格）。

    「隔一格」这个条件不能少，否则标题里的叠字（邓小平爷爷植树）会被误判。
    """
    big = [c for ln in lines for c in ln.visible_chars() if c.size >= 24 and _is_cjk(c.char)]
    twins = [
        c
        for c in big
        if any(
            o is not c
            and o.char == c.char
            and abs(o.bbox[1] - c.bbox[1]) < 3
            and abs(o.cx - c.cx) > c.size * 1.2
            for o in big
        )
    ]
    # 普通对偶句也可能在同一行重复一个大字（如“站如松，坐如钟”）。真正的
    # 田字格则至少是一个黑字加两个描红字，保留同一基线至少三个候选的行。
    rows: dict[float, list[Char]] = {}
    for char in twins:
        rows.setdefault(round(char.bbox[1], 0), []).append(char)
    grid = [
        char
        for row in rows.values()
        if max(Counter(item.char for item in row).values(), default=0) >= 3
        for char in row
    ]
    return grid if len(grid) >= 4 else []


def split_after_class(body: list[Line]) -> tuple[list[Line], list[Line]]:
    """按最靠上的课后标志（练习题 / 会认字条 / 田字格）把正文区一分为二。"""
    grid_y = [c.bbox[1] for c in _grid_chars(body)]
    strip_groups = recognize_strip_groups(body)
    strip_y = [body[strip_groups[-1][0]].y0] if strip_groups else []
    marks = [ln.y0 for ln in body if _is_exercise_line(ln)] + strip_y + grid_y
    if not marks:
        return body, []
    cut = min(marks)
    lesson = [ln for ln in body if ln.y0 < cut - 1]
    after = [ln for ln in body if ln.y0 >= cut - 1]

    # 拼音课常把会认字条放在中间，下面继续安排“读一读”儿歌。会认字条仍归
    # 课后，但朗读区要重新接回课文续页，不能随第一次切分一起丢掉。
    read_aloud = next((ln for ln in after if _is_read_aloud_label(ln)), None)
    if read_aloud is not None:
        lesson.extend(ln for ln in after if ln.y0 >= read_aloud.y0 - 1)
        after = [ln for ln in after if ln.y0 < read_aloud.y0 - 1]
    return lesson, after


def extract_lesson(
    body: list[Line], dominant: float | None = None
) -> tuple[dict | None, list[Line]]:
    """抽取课文单元，返回 (课文 JSON, 未消费的行)。

    dominant 传整页正文的主字号：课后被切走后，剩下的几行不足以判断字号，
    识字表那种「标题 + 一行小字」的页面会把标题误当成正文。
    """
    if not body:
        return None, []
    if dominant is None:
        dominant = _dominant_size(body)

    lesson_no = title = subtitle = None
    consumed: set[int] = set()

    # 口语交际页用多套字号表达导语、示例和提示，不能用单一正文主字号筛选。
    # 栏目标签下方字号最大的短行才是篇目标题（如“口语交际 / 我说你做”）。
    mixed_section = next(
        (
            ln
            for ln in body
            if ln.text() in MIXED_SECTION_LABELS
            and any(font.startswith("FZHTJW") for font in ln.fonts)
        ),
        None,
    )
    mixed_title = None
    if mixed_section is not None:
        mixed_title = max(
            (
                ln
                for ln in body
                if ln.y0 > mixed_section.y1
                and any(_is_cjk(char.char) for char in ln.visible_chars())
            ),
            key=lambda ln: ln.max_size,
            default=None,
        )
    read_aloud = next((ln for ln in body if _is_read_aloud_label(ln)), None)

    # 标题：字号大于正文主字号的行（课题 > 篇目标题）
    numbered = {id(ln) for ln in body if _has_lesson_number(ln)}
    big = (
        [mixed_title]
        if mixed_title is not None
        else [
            ln
            for ln in body
            if (ln.size > dominant + 0.5 or id(ln) in numbered)
            and (read_aloud is None or ln.y0 < read_aloud.y0)
            and not _is_latin_number(ln)
        ]
    )
    if (
        not big
        and len(body) == 1
        and body[0].max_size >= 24
        and not _is_latin_number(body[0])
    ):
        # 跨页图文篇目可能把大标题单独放在一整页（如一上“我是中国人”）。
        # 此时唯一一行本身会被统计成正文主字号，需按独立标题页识别。
        big = [body[0]]
    heads: list[tuple[Line, str, str]] = []
    for ln in big:
        chars = [c for c in ln.visible_chars() if not c.font.startswith(LATIN_FONTS)]
        digits = [c for c in ln.visible_chars() if c.font.startswith(LATIN_FONTS)]
        if digits and lesson_no is None:
            lesson_no = "".join(c.char for c in digits)
        text = re.sub(r"\s+", "", "".join(c.char for c in chars))
        if text:
            note_mark = "".join(re.findall(r"[①-⑳]", text))
            heads.append((ln, re.sub(r"[①-⑳]", "", text), note_mark))
            consumed.add(id(ln))
    note_mark = ""
    if heads:
        if len(heads) >= 2 and lesson_no is not None:
            title, subtitle = heads[0][1], heads[1][1]
            note_mark = heads[1][2] or heads[0][2]
        else:
            title = heads[0][1]
            note_mark = heads[0][2]

    # 栏目标签：标题上方的黑体小字（我爱阅读 / 口语交际 / 日积月累 …）
    section = mixed_section.text() if mixed_section is not None else None
    if mixed_section is not None:
        consumed.add(id(mixed_section))
    title_y = heads[0][0].y0 if heads else float("inf")
    for ln in body:
        text = ln.text()
        if (
            id(ln) not in consumed
            and ln.y0 < title_y
            and len(text) <= 8
            and any(f.startswith((SECTION_FONT, "FZHTJW")) for f in ln.fonts)
        ):
            section = text
            consumed.add(id(ln))
            break

    # 作者行：仿宋、带朝代方括号
    period = author = source = None
    author_line = None
    for ln in body:
        if id(ln) in consumed:
            continue
        m = AUTHOR_RE.match(ln.text())
        if m and ln.size < dominant:
            period = m.group("年代").strip()
            author = re.sub(r"\s+", "", m.group("作者"))
            author_line = ln
            consumed.add(id(ln))
            break

    # 乐府、民歌等篇目在标题下直接标注作品来源，而不是作者。
    source_line = None
    for ln in body:
        if id(ln) in consumed:
            continue
        text = re.sub(r"\s+", "", ln.text())
        if SOURCE_LINE_RE.fullmatch(text) and ln.size < dominant:
            source = text
            source_line = ln
            consumed.add(id(ln))
            break

    # 注释（①…）：字号小于正文，可能折行（续行不带序号，跟在上一行下面）
    notes: list[dict] = []
    last_note: Line | None = None
    for ln in body:
        if id(ln) in consumed or ln.size >= dominant:
            continue
        if NOTE_RE.match(ln.text()):
            notes.append({"文本": ln.text(), "bbox": round_box(ln.bbox)})
            consumed.add(id(ln))
            last_note = ln
        elif last_note is not None and 0 <= ln.y0 - last_note.y1 < ln.size * 1.2:
            notes[-1]["文本"] = f"{notes[-1]['文本']}{ln.text()}"
            notes[-1]["bbox"] = round_box(union(tuple(notes[-1]["bbox"]), ln.bbox))
            consumed.add(id(ln))
            last_note = ln

    # 正文行：主字号
    text_lines = [
        ln
        for ln in body
        if id(ln) not in consumed
        and (
            mixed_section is not None
            or (read_aloud is not None and ln.y0 >= read_aloud.y0)
            or abs(ln.size - dominant) < 0.6
        )
        and (
            mixed_section is None
            or any(_is_cjk(char.char) for char in ln.visible_chars())
        )
        and ln.visible_chars()
    ]
    if not title and not text_lines:
        return None, body

    if read_aloud is not None:
        leading = [ln for ln in text_lines if ln.y0 < read_aloud.y0]
        selection = [ln for ln in text_lines if ln.y0 >= read_aloud.y0]
        stream, first_indent = _char_stream(leading)
        content = _chars_to_clauses(stream)
        paragraph = max((unit["段落"] for unit in content), default=0)

        # “读一读”和紧随其后的篇名各自成行；正文再按标点断句。否则前面的
        # 无标点词条会与栏目名、篇名一路粘到儿歌第一处逗号。
        for line in selection[:2]:
            paragraph += 1
            items = [(char, paragraph) for char in line.visible_chars()]
            if items:
                content.append(_unit(items, len(content) + 1))
        poem_stream: list[tuple[Char, int]] = []
        if len(selection) > 2:
            paragraph += 1
            for line in selection[2:]:
                poem_stream.extend((char, paragraph) for char in line.visible_chars())
        content.extend(_chars_to_clauses(poem_stream))
        for no, unit in enumerate(content, 1):
            unit["序号"] = no
    else:
        stream, first_indent = _char_stream(text_lines)
        content = _chars_to_clauses(stream)

    if not title and not content:
        return None, body

    used = consumed | {id(ln) for ln in text_lines}
    rest = [ln for ln in body if id(ln) not in used]
    lesson = {
        "课号": lesson_no,
        "栏目": section,
        "课题": title if subtitle else None,
        "标题": subtitle or title,
        "标题注释号": note_mark or None,
        "作者": author,
        "年代": period,
        "国别": None,
        "译者": None,
        "出处": source,
        "作者出处": "作者行" if author else ("出处行" if source else None),
        "注释": notes,
        "正文": content,
        "首行缩进": first_indent,
    }
    # 作者多半不在正文旁边，而写在脚注里
    got, mark = attribution.from_notes(notes)
    if got:
        for key, value in got.items():
            if lesson.get(key) is None:
                lesson[key] = value
        lesson["作者出处"] = lesson["作者出处"] or (f"注释{mark}" if mark else "注释")
    if author_line is not None:
        lesson["作者行"] = {"文本": author_line.text(), "bbox": round_box(author_line.bbox)}
    if source_line is not None:
        lesson["出处行"] = {"文本": source_line.text(), "bbox": round_box(source_line.bbox)}
    return lesson, rest


def extract_after_class(
    body: list[Line], rules: list[tuple[float, float, float]]
) -> dict | None:
    """抽取课后单元：会认字条、会写字表、练习题。"""
    if not body:
        return None
    used: set[int] = set()

    # 会认字条：整行汉字且每个字都带注音
    recognize: list[dict] = []
    for ln in body:
        if _is_recognize_strip(ln):
            recognize.extend(
                {"字": c.char, "拼音": c.pinyin}
                for c in ln.visible_chars()
                if _is_cjk(c.char)
            )
            used.add(id(ln))

    # 会写字表：田字格里的大字，黑字 + 红色描红字成对出现，去重取每对第一个
    write: list[str] = []
    grid_chars = _grid_chars([ln for ln in body if id(ln) not in used])
    grid_ids = {id(c) for c in grid_chars}
    for ln in body:
        if id(ln) not in used and any(id(c) in grid_ids for c in ln.visible_chars()):
            used.add(id(ln))
    if grid_chars:
        mid = (min(c.bbox[0] for c in grid_chars) + max(c.bbox[2] for c in grid_chars)) / 2
        cells: list[Char] = []
        for c in sorted(grid_chars, key=lambda c: (c.cx >= mid, round(c.bbox[1]), c.cx)):
            if cells and cells[-1].char == c.char and abs(cells[-1].bbox[1] - c.bbox[1]) < 3:
                continue  # 描红重复字
            cells.append(c)
        write = [c.char for c in cells]

    # 练习题：题号位（制表符）开头是一道题，◇ 是题内子项，其余行归入上一题
    exercises: list[dict] = []
    others: list[dict] = []
    right = line_right_edge(body)
    prev_line: Line | None = None
    for ln in body:
        if id(ln) in used:
            continue
        segs = ln.segments(rules)
        if not segs:
            continue
        bucket = exercises[-1]["内容"] if exercises else others
        if prev_line is not None and bucket and is_wrapped(
            prev_line, bucket[-1]["文本"], ln, right
        ):
            merge_item(bucket[-1], segs[0])
            segs = segs[1:]
        elif (
            prev_line is not None
            and not bucket
            and exercises
            and is_wrapped(prev_line, exercises[-1]["要求"], ln, right)
        ):
            exercises[-1]["要求"] += segs[0]["文本"]  # 题干折行
            segs = segs[1:]
        prev_line = ln
        if not segs:
            continue
        if _is_exercise_line(ln):
            exercises.append(
                {
                    "序号": len(exercises) + 1,
                    "要求": " ".join(s["文本"] for s in segs),
                    "内容": [],
                    "bbox": round_box(ln.bbox),
                }
            )
            continue
        for seg in segs:
            seg["类型"] = "子项" if seg["文本"].startswith(BULLET) else "词句"
            (exercises[-1]["内容"] if exercises else others).append(seg)

    if not (recognize or write or exercises or others):
        return None
    return {
        "生字": {"会认": recognize, "会写": write},
        "练习": exercises,
        "其他": others,
    }
