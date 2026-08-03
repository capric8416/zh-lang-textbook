"""拼音注音字体解码。

课本里的拼音用的是方正「HanyuXi-JZ」拼音字体：带声调的元音被映射成了
ASCII 大写字母（PDF 的 ToUnicode 表就是这么写的），所以直接取文本会得到
``yGng`` 这种乱码。下表由全书 1319 组「汉字 ↔ 注音」对照自动标定得出
（用 pypinyin 校验，无冲突），键盘布局上刚好是每个元音一组四声：

    a: Q W A S      e: E R D F      i: U I J K
    o: T Y G H      u: O P L M      ü: N B V C
"""

from __future__ import annotations

import unicodedata

# 大写字母 -> 带声调元音
TONE_CIPHER: dict[str, str] = {
    "Q": "ā", "W": "á", "A": "ǎ", "S": "à",
    "E": "ē", "R": "é", "D": "ě", "F": "è",
    "U": "ī", "I": "í", "J": "ǐ", "K": "ì",
    "T": "ō", "Y": "ó", "G": "ǒ", "H": "ò",
    "O": "ū", "P": "ú", "L": "ǔ", "M": "ù",
    # ü 一行在本册中只出现了 ǚ / ǜ，其余两个按同组规律补全
    "N": "ǖ", "B": "ǘ", "V": "ǚ", "C": "ǜ",
    "v": "ü",
}

RUBY_FONT_PREFIX = "HanyuXi"


def is_ruby_font(font: str) -> bool:
    """是否为拼音注音字体。"""
    return font.startswith(RUBY_FONT_PREFIX)


def decode(raw: str) -> str:
    """把注音字体的原始文本还原成带声调拼音。"""
    return "".join(TONE_CIPHER.get(c, c) for c in raw).strip()


def toneless(pinyin: str) -> str:
    """去掉声调，便于比对（ü 归一成 v）。"""
    plain = "".join(
        c for c in unicodedata.normalize("NFD", pinyin) if unicodedata.category(c) != "Mn"
    )
    return plain.replace("ü", "v")
