"""书末附录：识字表 / 写字表 / 词语表。

三张表的版式一样：大标题，下面按「阅读 / 识字」分组，每组里一行一课
（行首是课号或「语文园地X」），排不下就折到下一行（下一行没有行首标签）。
差别只在每行的内容：

    识字表  1 咏 贺 妆 …   带注音的单字
    写字表  1 诗碧妆绿丝剪童归  单字，不带注音
    词语表  2 春天 寻找 眉毛 …  词语，空格分隔
"""

from __future__ import annotations

import re

from .blocks import Line, round_box

STROKE_TABLE = "笔画名称表"
RADICAL_TABLE = "常用偏旁名称表"
COLUMN_TABLES = {STROKE_TABLE, RADICAL_TABLE}
TITLE_RE = re.compile(
    rf"^(识字表|写字表|词语表|{STROKE_TABLE}|{RADICAL_TABLE})$"
)
LABEL_RE = re.compile(r"^(\d{1,2}|语文园地[一二三四五六七八九十]+)")
NOTE_RE = re.compile(r"^[①-⑳]")
SUMMARY_RE = re.compile(r"^[（(]?共\d+个(?:生字|字)[）)]?$")
GROUP_FONT = "FZS3"  # 「阅读」「识字」等分组标签的字体名前缀
GROUP_NAMES = {"阅读", "识字", "汉语拼音"}
TITLE_MIN_SIZE = 20

RADICAL_BY_NAME = {
    "单人旁": "亻",
    "八字头": "八",
    "人字头": "人",
    "斜刀头": "⺈",
    "包字头": "勹",
    "倒八": "丷",
    "言字旁": "讠",
    "双耳旁": "阝",
    "提土旁": "土",
    "提手旁": "扌",
    "草字头": "艹",
    "口字旁": "口",
    "国字框": "囗",
    "三撇": "彡",
    "反犬旁": "犭",
    "折文": "夂",
    "门字框": "门",
    "三点水": "氵",
    "宝盖头": "宀",
    "走之底": "辶",
    "女字旁": "女",
    "绞丝旁": "纟",
    "木字旁": "木",
    "日字旁": "日",
    "月字旁": "月",
    "四点底": "灬",
    "禾字旁": "禾",
    "穴字头": "穴",
    "竹字头": "竹",
    "立刀旁": "刂",
    "京字头": "亠",
    "两点水": "冫",
    "力字旁": "力",
    "又字旁": "又",
    "大字头": "大",
    "双人旁": "彳",
    "食字旁": "饣",
    "广字头": "广",
    "竖心旁": "忄",
    "尸字头": "尸",
    "弓字旁": "弓",
    "子字旁": "子",
    "王字旁": "王",
    "车字旁": "车",
    "牛字旁": "牜",
    "反文旁": "攵",
    "爪字头": "爫",
    "火字旁": "火",
    "户字头": "户",
    "示字旁": "礻",
    "心字底": "心",
    "目字旁": "目",
    "皿字底": "皿",
    "金字旁": "钅",
    "病字头": "疒",
    "衣字旁": "衤",
    "页字旁": "页",
    "虫字旁": "虫",
    "舌字旁": "舌",
    "米字旁": "米",
    "走字底": "走",
    "足字旁": "足",
    "雨字头": "雨",
}

STROKE_ROWS = [
    ("㇐", "横", "一十"),
    ("㇑", "竖", "上木"),
    ("㇒", "撇", "手八"),
    ("㇔", "点", "火头"),
    ("㇏", "捺", "火人"),
    ("㇀", "提", "虫我"),
    ("㇕", "横折", "口五"),
    ("㇇", "横撇", "了水"),
    ("㇖", "横钩", "你"),
    ("㇗", "竖折", "牙山"),
    ("㇄", "竖弯", "西四"),
    ("㇙", "竖提", "比长"),
    ("㇚", "竖钩", "可小"),
    ("㇜", "撇折", "去云"),
    ("㇛", "撇点", "女妈"),
    ("㇁", "弯钩", "手子"),
    ("㇂", "斜钩", "我"),
    ("㇃", "卧钩", "心"),
    ("㇅", "横折折", "凹"),
    ("㇍", "横折弯", "船"),
    ("㇊", "横折提", "话"),
    ("㇆", "横折钩", "用刀"),
    ("㇈", "横斜钩", "风"),
    ("㇞", "竖折折", "鼎"),
    ("㇋", "竖折撇", "专"),
    ("㇟", "竖弯钩", "七儿"),
    ("㇅", "横折折折", "凸"),
    ("㇋", "横折折撇", "及"),
    ("㇈", "横折弯钩", "九几"),
    ("㇌", "横撇弯钩", "那"),
    ("㇉", "竖折折钩", "马鸟"),
    ("㇎", "横折折折钩", "奶"),
]


def _clean(text: str) -> str:
    return re.sub(r"[\s①-⑳]", "", text)


def appendix_title(body: list[Line]) -> str | None:
    """这一页是不是某张表的首页，是就返回表名。"""
    for ln in body:
        if ln.size >= TITLE_MIN_SIZE and TITLE_RE.match(_clean(ln.text())):
            return _clean(ln.text())
    return None


def _split_label(line: Line) -> tuple[str | None, list, str]:
    """切掉行首的课号 / 语文园地标签，返回 (标签, 余下的字, 余下的文本)。

    文本要保留词间空格 —— 词语表就靠它分词。
    """
    text = line.text()
    chars = [c for c in line.visible_chars() if c.char.strip()]
    m = LABEL_RE.match(text)
    if not m:
        return None, chars, text.strip()
    want = m.group(1)
    i = 0
    while i < len(chars) and want:
        if chars[i].char == want[0]:
            want = want[1:]
        i += 1
    return m.group(1), chars[i:], text[m.end() :].strip()


def _row(label: str | None, chars: list, text: str) -> dict:
    return {
        "标签": label,
        "字": [
            {"字": c.char, "拼音": c.pinyin}
            for c in chars
            if "一" <= c.char <= "鿿"
        ],
        "文本": text,
    }


def _radical_rows(body: list[Line]) -> list[dict]:
    """按左栏再右栏提取「偏旁 / 名称 / 例字」三列。"""
    left: list[dict] = []
    right: list[dict] = []
    for line in body:
        spans = [s for s in line.spans if s.text.strip()]
        for i, span in enumerate(spans):
            name = _clean(span.text)
            radical = RADICAL_BY_NAME.get(name)
            if radical is None or i + 1 >= len(spans):
                continue
            example = _clean(spans[i + 1].text)
            if not example or example in RADICAL_BY_NAME:
                continue
            row = {
                "标签": radical,
                "字": [],
                "文本": "",
                "内容": [radical, name, example],
            }
            (left if span.bbox[0] < 260 else right).append(row)
    return left + right


def _stroke_rows() -> list[dict]:
    return [
        {"标签": stroke, "字": [], "文本": "", "内容": [stroke, name, example]}
        for stroke, name, example in STROKE_ROWS
    ]


def _column_order(body: list[Line], split_x: float = 255) -> list[Line]:
    """把双栏附录按左栏、右栏的阅读顺序拆开。"""
    columns: list[list[Line]] = [[], []]
    for line in body:
        for column, spans in enumerate(
            (
                [span for span in line.spans if (span.bbox[0] + span.bbox[2]) / 2 < split_x],
                [span for span in line.spans if (span.bbox[0] + span.bbox[2]) / 2 >= split_x],
            )
        ):
            if not spans:
                continue
            x0 = min(span.bbox[0] for span in spans)
            x1 = max(span.bbox[2] for span in spans)
            chars = [char for char in line.chars if x0 - 0.5 <= char.cx <= x1 + 0.5]
            columns[column].append(Line(spans, chars))
    return columns[0] + columns[1]


def parse_appendix(body: list[Line]) -> dict | None:
    """把一页附录拆成 {名称, 分组[], 注释[]}。"""
    appendix_name = appendix_title(body)
    if appendix_name in COLUMN_TABLES:
        rows = _stroke_rows() if appendix_name == STROKE_TABLE else _radical_rows(body)
        return {
            "名称": appendix_name,
            "分组": [{"名称": None, "行": rows}],
            "注释": [],
        }

    if appendix_name == "写字表":
        body = _column_order(body)

    title = None
    groups: list[dict] = []
    notes: list[dict] = []
    for ln in body:
        text = ln.text()
        if ln.size >= TITLE_MIN_SIZE and TITLE_RE.match(_clean(text)):
            title = _clean(text)
            continue
        if NOTE_RE.match(text) and ln.size < 14:
            notes.append({"文本": text, "bbox": round_box(ln.bbox)})
            continue
        if SUMMARY_RE.match(_clean(text)):
            continue
        clean = _clean(text)
        group_name = next(
            (name for name in GROUP_NAMES if clean == name or clean == name * 2),
            None,
        )
        if group_name and any(f.startswith(GROUP_FONT) for f in ln.fonts):
            groups.append({"名称": group_name, "行": []})
            continue
        label, chars, text = _split_label(ln)
        if not chars:
            continue
        if not groups:
            groups.append({"名称": None, "行": []})
        rows = groups[-1]["行"]
        if label is None and rows:  # 折行，接着上一行
            row = _row(None, chars, text)
            rows[-1]["字"] += row["字"]
            rows[-1]["文本"] += " " + row["文本"]
        else:
            rows.append(_row(label, chars, text))
    if not (title or groups):
        return None
    return {"名称": title, "分组": groups, "注释": notes}


def _content(name: str | None, row: dict) -> list:
    """按表的种类把一行整理成最终内容。"""
    if name in COLUMN_TABLES:
        return row["内容"]
    if name == "识字表":
        return row["字"]
    if name == "词语表":
        return row["文本"].split()
    return [c["字"] for c in row["字"]]  # 写字表：单字


def merge_appendices(pages: list[dict]) -> list[dict]:
    """把逐页的附录合并成整张表。"""
    units: list[dict] = []
    current: dict | None = None
    for page in pages:
        part = page.get("附录")
        if not part:
            continue
        if part["名称"] or current is None:
            current = {"名称": part["名称"], "页码": [], "注释": [], "分组": []}
            units.append(current)
        current["页码"].append(page["页码"])
        current["注释"] += part["注释"]
        for group in part["分组"]:
            rows = group["行"]
            if group["名称"] is None and current["分组"]:
                prev = current["分组"][-1]["行"]
                if rows and rows[0]["标签"] is None and prev:  # 跨页折行
                    prev[-1]["字"] += rows[0]["字"]
                    prev[-1]["文本"] += " " + rows[0]["文本"]
                    rows = rows[1:]
                prev += rows
            else:
                current["分组"].append({"名称": group["名称"], "行": list(rows)})

    for unit in units:
        for group in unit["分组"]:
            group["行"] = [
                {"标签": r["标签"], "内容": _content(unit["名称"], r)}
                for r in group["行"]
                if r.get("字") or r.get("内容")
            ]
        unit["条数"] = sum(len(g["行"]) for g in unit["分组"])
    return units
