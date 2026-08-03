"""版面分区：页眉 / 页脚 / 右边栏 / 正文区。"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .blocks import Line, round_box

# 相对页高/页宽的分区阈值
HEADER_BAND = 0.075  # 页眉带：页面顶部 7.5%
FOOTER_BAND = 0.885  # 页脚带：页面底部 11.5%
SIDEBAR_X = 0.80  # 右边栏带：页面右侧 20%
SIDEBAR_MAX_W = 0.18  # 右边栏元素的最大宽度（占页宽）

WATERMARK_RE = re.compile(r"仅供个人学习使用")
_PAGENO_RE = re.compile(r"^\d{1,3}$")


def page_number(text: str) -> str | None:
    """页脚页码。个别页面页码是叠印的（'9494'），取其一半。"""
    text = text.strip()
    if _PAGENO_RE.match(text):
        return text
    if text.isdigit() and len(text) % 2 == 0:
        half = len(text) // 2
        if text[:half] == text[half:] and len(text[:half]) <= 3:
            return text[:half]
    return None


@dataclass
class Regions:
    header: list[Line] = field(default_factory=list)
    footer: list[Line] = field(default_factory=list)
    sidebar: list[Line] = field(default_factory=list)
    body: list[Line] = field(default_factory=list)


def split_regions(lines: list[Line], width: float, height: float) -> Regions:
    r = Regions()
    header_y = height * HEADER_BAND
    footer_y = height * FOOTER_BAND
    for line in lines:
        text = line.text()
        if line.y1 <= header_y:
            r.header.append(line)
        elif line.y0 >= footer_y and (page_number(text) or WATERMARK_RE.search(text)):
            r.footer.append(line)
        else:
            r.body.append(line)
    r.sidebar = _detect_sidebar(r.body, width)
    taken = {id(ln) for ln in r.sidebar}
    r.body = [ln for ln in r.body if id(ln) not in taken]
    return r


def _detect_sidebar(body: list[Line], width: float) -> list[Line]:
    """右边栏：贴右页边、窄、且与正文行不同排（不共享行高）的成组文本。

    本册课本正文可排到 x≈488（0.94 页宽），所以右边栏必须同时满足「窄」和
    「与正文不同排」两个条件，否则会把折行到右侧的正文误判成边栏。
    """
    x_gate = width * SIDEBAR_X
    max_w = width * SIDEBAR_MAX_W
    cands = [
        ln
        for ln in body
        if ln.x0 >= x_gate
        and (ln.bbox[2] - ln.x0) <= max_w
        and not any(
            other is not ln
            and other.x0 < x_gate
            and min(other.y1, ln.y1) - max(other.y0, ln.y0) > 0
            for other in body
        )
    ]
    return cands if len(cands) >= 2 else []


def header_json(lines: list[Line], width: float) -> dict | None:
    if not lines:
        return None
    line = max(lines, key=lambda ln: len(ln.text()))
    box = line.bbox
    side = "右" if (box[0] + box[2]) / 2 > width / 2 else "左"
    return {"文本": line.text(), "位置": f"{side}上角标", "bbox": round_box(box)}


def footer_json(lines: list[Line]) -> dict | None:
    if not lines:
        return None
    out: dict = {"页码": None, "水印": None, "bbox": None}
    box = None
    for line in lines:
        text = line.text()
        box = line.bbox if box is None else (
            min(box[0], line.bbox[0]), min(box[1], line.bbox[1]),
            max(box[2], line.bbox[2]), max(box[3], line.bbox[3]),
        )
        if page_number(text):
            out["页码"] = page_number(text)
        elif WATERMARK_RE.search(text):
            out["水印"] = text
    out["bbox"] = round_box(box) if box else None
    return out
