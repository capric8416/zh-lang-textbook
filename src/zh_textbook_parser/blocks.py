"""排版块抽取：把 PDF 页面还原成「行」和「字」，并把拼音注音挂回汉字。

PyMuPDF 给出的 block/line 切分对这本课本并不可靠（注音、全角空格、填空线
会把一行切碎），所以这里从 span 级别按几何位置重新聚类成行，再把行拆成
带坐标的单字，便于注音对齐与按标点切分。
"""

from __future__ import annotations

from dataclasses import dataclass, field

import fitz

from .pinyin_font import decode, is_ruby_font

KENTEN_FONT = "Kenten"  # 着重号（字下的点），不是正文

# 字体里没给 Unicode 映射、落到私用区的字形
GLYPH_FIX = {"\ue823": "\u2e97"}  # 「慕」字底的心字底 ⺗（CJK RADICAL HEART TWO）


def fix_glyphs(text: str) -> str:
    """补上私用区字形的 Unicode，并去掉控制字符。"""
    return "".join(
        GLYPH_FIX.get(c, c) for c in text if c >= " " or c == "\t"
    )

BBox = tuple[float, float, float, float]

LINE_OVERLAP_RATIO = 0.45  # 同一行的 span 垂直重叠比例阈值
RUBY_MAX_GAP = 14.0  # 注音与被注汉字的最大垂直间距（pt）
BLANK_GAP = 20.0  # 行内视为「填空线」的水平空隙（pt）
RUBY_MAX_SIZE = 13.0  # 注音字号上限：本书真注音 9~12pt
RUBY_SIZE_RATIO = 0.75  # 注音相对被注字的最大字号比

_SPACES = "    　\t"


def union(a: BBox, b: BBox) -> BBox:
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def round_box(b: BBox) -> list[float]:
    return [round(v, 1) for v in b]


def normalize(text: str) -> str:
    """折叠各种空白，去掉控制字符和首尾空白。"""
    text = "".join(c for c in text if c >= " " or c in "\t")
    for sp in _SPACES:
        text = text.replace(sp, " ")
    while "  " in text:
        text = text.replace("  ", " ")
    return text.strip()


@dataclass
class Span:
    text: str
    bbox: BBox
    size: float
    font: str


@dataclass
class Char:
    """一个字（含坐标与注音）。"""

    char: str
    bbox: BBox
    size: float
    font: str
    pinyin: str | None = None

    @property
    def cx(self) -> float:
        return (self.bbox[0] + self.bbox[2]) / 2


@dataclass
class Line:
    """一个排版行。"""

    spans: list[Span]
    chars: list[Char] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.chars:
            self.chars = [c for s in self.spans for c in _split_span(s)]

    @property
    def bbox(self) -> BBox:
        box = self.spans[0].bbox
        for s in self.spans[1:]:
            box = union(box, s.bbox)
        return box

    @property
    def x0(self) -> float:
        return self.bbox[0]

    @property
    def y0(self) -> float:
        return self.bbox[1]

    @property
    def y1(self) -> float:
        return self.bbox[3]

    @property
    def size(self) -> float:
        """行内出现最多的字号（按可见字符数加权）。"""
        weight: dict[float, int] = {}
        for c in self.chars:
            if c.char in _SPACES:
                continue
            weight[round(c.size, 1)] = weight.get(round(c.size, 1), 0) + 1
        return max(weight, key=lambda k: weight[k]) if weight else 0.0

    @property
    def max_size(self) -> float:
        return max((round(s.size, 1) for s in self.spans), default=0.0)

    @property
    def fonts(self) -> list[str]:
        return sorted({s.font for s in self.spans})

    def text(self, mark_blank: bool = False) -> str:
        """行文本；mark_blank=True 时把大空隙还原成填空线 ＿＿。"""
        out: list[str] = []
        prev: Span | None = None
        for s in self.spans:
            if prev is not None:
                gap = s.bbox[0] - prev.bbox[2]
                if mark_blank and gap > BLANK_GAP:
                    out.append("＿＿")
                elif gap > min(s.size, prev.size) * 0.35:
                    out.append(" ")  # 排版空隙，保留成一个空格
            out.append(s.text)
            prev = s
        return normalize("".join(out))

    def segments(self, rules: list[tuple[float, float, float]]) -> list[dict]:
        """按大空隙把行切段：空隙下有横线的是填空（还原成 ＿＿），否则是分栏。

        rules 是页面上的横线段 (x0, x1, y)，来自矢量绘图。
        """
        parts: list[list[Span]] = [[]]
        prev: Span | None = None
        for s in self.spans:
            gap = s.bbox[0] - prev.bbox[2] if prev else 0.0
            if prev is not None and gap > BLANK_GAP and not _underlined(
                prev.bbox[2], s.bbox[0], self.y0, self.y1, rules
            ):
                parts.append([])  # 分栏：另起一段
            parts[-1].append(s)
            prev = s

        out: list[dict] = []
        for group in parts:
            if not group:
                continue
            gx0, gx1 = group[0].bbox[0], group[-1].bbox[2]
            # 复用原行已挂好注音的 Char，不要重新切分
            line = Line(group, [c for c in self.chars if gx0 - 0.5 <= c.cx <= gx1 + 0.5])
            text = line.text(mark_blank=True)
            if not text:
                continue
            if _touching_rule(gx0, self.y0, self.y1, rules, before=True):
                text = f"＿＿{text}"  # 开头就是填空线
            if _touching_rule(gx1, self.y0, self.y1, rules, before=False):
                text = f"{text}＿＿"
            out.append(
                {
                    "文本": text,
                    "注音": line.pinyin_items(),
                    "bbox": round_box(line.bbox),
                }
            )
        return out

    def visible_chars(self) -> list[Char]:
        return [c for c in self.chars if c.char not in _SPACES]

    def pinyin_items(self) -> list[dict]:
        return [
            {"字": c.char, "拼音": c.pinyin} for c in self.visible_chars() if c.pinyin
        ]


def _split_span(s: Span) -> list[Char]:
    """把 span 按等宽切成单字（CJK 等宽排版，够用）。"""
    x0, y0, x1, y1 = s.bbox
    n = max(len(s.text), 1)
    w = (x1 - x0) / n
    return [
        Char(ch, (x0 + w * i, y0, x0 + w * (i + 1), y1), s.size, s.font)
        for i, ch in enumerate(s.text)
    ]


def _collect_spans(page: fitz.Page) -> tuple[list[Span], list[Span]]:
    """返回 (正文 span, 注音 span)。"""
    body: list[Span] = []
    ruby: list[Span] = []
    for block in page.get_text("dict")["blocks"]:
        if block["type"] == 1:  # 图片块
            continue
        for line in block["lines"]:
            for s in line["spans"]:
                if not s["text"].strip() or s["font"].startswith(KENTEN_FONT):
                    continue
                text = fix_glyphs(s["text"])
                if not text.strip():
                    continue
                if is_ruby_font(s["font"]):
                    if s["size"] < RUBY_MAX_SIZE:
                        ruby.append(Span(text, tuple(s["bbox"]), s["size"], s["font"]))
                    else:
                        # 正文里的拼音字母（喜鹊教的「a—o—e」），不是注音
                        body.append(
                            Span(decode(text), tuple(s["bbox"]), s["size"], s["font"])
                        )
                    continue
                body.append(Span(text, tuple(s["bbox"]), s["size"], s["font"]))
    return body, ruby


def _cluster_lines(spans: list[Span]) -> list[Line]:
    """按垂直重叠把 span 聚成行。"""
    groups: list[list[Span]] = []
    for s in sorted(spans, key=lambda s: (s.bbox[1], s.bbox[0])):
        for g in groups:
            gy0 = min(x.bbox[1] for x in g)
            gy1 = max(x.bbox[3] for x in g)
            overlap = min(gy1, s.bbox[3]) - max(gy0, s.bbox[1])
            height = min(gy1 - gy0, s.bbox[3] - s.bbox[1])
            if height > 0 and overlap / height >= LINE_OVERLAP_RATIO:
                g.append(s)
                break
        else:
            groups.append([s])
    lines = [Line(sorted(g, key=lambda s: s.bbox[0])) for g in groups]
    return sorted(lines, key=lambda ln: (round(ln.y0), ln.x0))


def _attach_rubies(lines: list[Line], rubies: list[Span]) -> None:
    """把注音挂到正下方、水平最接近的那个字上。"""
    for r in rubies:
        rx0, _, rx1, ry1 = r.bbox
        rcx = (rx0 + rx1) / 2
        best: tuple[float, float, Char] | None = None
        for line in lines:
            if line.y1 < ry1 - 3 or line.y0 - ry1 > RUBY_MAX_GAP:
                continue
            for c in line.visible_chars():
                # 逐字判断上下距离：一行里可能混着 10.5pt 的说明和 16pt 的词条
                if c.bbox[1] < ry1 - 3 or c.bbox[1] - ry1 > RUBY_MAX_GAP:
                    continue
                if r.size > c.size * RUBY_SIZE_RATIO:  # 注音总比被注的字小一圈
                    continue
                overlap = min(rx1, c.bbox[2]) - max(rx0, c.bbox[0])
                if overlap <= 0:
                    continue
                key = (abs(c.cx - rcx), -overlap, c)
                if best is None or key[:2] < best[:2]:
                    best = key
        if best is not None:
            best[2].pinyin = decode(r.text)


def page_lines(page: fitz.Page) -> list[Line]:
    """抽取一页的所有排版行（注音已挂回单字）。"""
    body, rubies = _collect_spans(page)
    lines = _cluster_lines(body)
    _attach_rubies(lines, rubies)
    return lines


def _underlined(
    x0: float, x1: float, y0: float, y1: float, rules: list[tuple[float, float, float]]
) -> bool:
    """空隙下方（行内或基线附近）是否有横线 —— 填空题的下划线。"""
    for rx0, rx1, ry in rules:
        if not (y0 - 2 <= ry <= y1 + 6):
            continue
        cover = min(x1, rx1) - max(x0, rx0)
        if cover > (x1 - x0) * 0.5:
            return True
    return False


def _touching_rule(
    x: float,
    y0: float,
    y1: float,
    rules: list[tuple[float, float, float]],
    before: bool,
) -> bool:
    """x 的左边（before）或右边紧挨着一条横线 —— 段首/段尾的填空线。"""
    for rx0, rx1, ry in rules:
        if not (y0 - 2 <= ry <= y1 + 6):
            continue
        edge = rx1 if before else rx0
        if abs(edge - x) < 8 and (rx1 - rx0) > 15:
            return True
    return False


def page_rules(page: fitz.Page) -> list[tuple[float, float, float]]:
    """页面上的填空线：水平横线段，排除画在田字格框里的那条中线。"""
    raw: list[tuple[float, float, float]] = []
    boxes = []
    for d in page.get_drawings():
        r = d["rect"]
        if r.width > 20 and r.height < 3:
            raw.append((r.x0, r.x1, (r.y0 + r.y1) / 2))
        elif r.height > 5 and any(item[0] == "re" for item in d["items"]):
            boxes.append(r)
    return [
        rule
        for rule in raw
        if not any(
            b.x0 - 2 <= rule[0] and rule[1] <= b.x1 + 2 and b.y0 < rule[2] < b.y1
            for b in boxes
        )
    ]


def page_images(page: fitz.Page) -> list[BBox]:
    """页面上的图片块（插图、装饰、田字格底图等），过滤退化的零宽块。"""
    return [
        tuple(b["bbox"])
        for b in page.get_text("dict")["blocks"]
        if b["type"] == 1
        and b["bbox"][2] - b["bbox"][0] > 2
        and b["bbox"][3] - b["bbox"][1] > 2
    ]
