"""从课文注释里抽作者信息。

课本的作者不在正文旁边，而是写在脚注里，常见几种写法：

    ① 本文作者林颂英，选作课文时有改动。
    ① 本文作者是意大利的达·芬奇，译者张复生，选作课文时有改动。
    ① 本文根据欧庆林的 《首都百余万军民义务植树》改写，……
    ① 本文根据 《战国策·楚策四》相关内容改写。
    ① 本文选自商务印书馆《基本教科书国语第六册》，有改动。
    ① 本文由人民教育出版社小学语文室编写。
    ① 本文是民间故事，由李明才整理，选作课文时有改动。
"""

from __future__ import annotations

import re

_SEP = "，,。；;"  # 注释里的断句符，用作字段边界

FOREIGN_RE = re.compile(rf"本文作者是(?P<国别>[^的{_SEP}]+?)的(?P<作者>[^{_SEP}]+)")
AUTHOR_RE = re.compile(rf"本文作者(?:是)?(?P<作者>[^{_SEP}]+)")
ADAPT_RE = re.compile(rf"本文根据\s*(?P<作者>[^《{_SEP}]+?)的\s*《(?P<出处>[^》]+)》")
SOURCE_RE = re.compile(r"本文根据\s*《(?P<出处>[^》]+)》")
SELECT_RE = re.compile(rf"本文选自\s*(?P<出处>[^{_SEP}]+)")
COMPILE_RE = re.compile(rf"本文由(?P<作者>[^{_SEP}]+?)编写")
GENRE_RE = re.compile(r"本文是(?P<出处>民间故事|民间歌谣|民间传说)")
TRANSLATOR_RE = re.compile(rf"译者(?P<译者>[^{_SEP}]+)")
EDITOR_RE = re.compile(rf"由(?P<整理者>[^{_SEP}]+?)整理")

FIELDS = ("作者", "国别", "译者", "整理者", "出处")


def from_note(text: str) -> dict:
    """解析一条注释，返回其中的作者信息（没有就是空 dict）。"""
    got: dict[str, str] = {}
    for regex in (FOREIGN_RE, ADAPT_RE, COMPILE_RE, AUTHOR_RE):
        m = regex.search(text)
        if m:
            got.update({k: v.strip() for k, v in m.groupdict().items() if v})
            break
    if "本文根据" in text and "出处" not in got:
        books = re.findall(r"《([^》]+)》", text)
        if books:
            got["出处"] = "、".join(books)
    for regex in (SOURCE_RE, SELECT_RE, GENRE_RE, TRANSLATOR_RE, EDITOR_RE):
        m = regex.search(text)
        if m:
            for k, v in m.groupdict().items():
                if v and k not in got:
                    got[k] = v.strip()
    return {k: v for k, v in got.items() if k in FIELDS}


def from_notes(notes: list[dict]) -> tuple[dict, str | None]:
    """在一组注释里找作者信息，返回 (字段, 来源注释的序号标记)。"""
    for note in notes:
        got = from_note(note["文本"])
        if got:
            mark = re.match(r"\s*([①-⑳])", note["文本"])
            return got, (mark.group(1) if mark else None)
    return {}, None
