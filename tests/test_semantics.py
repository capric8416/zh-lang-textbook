import unittest

from zh_textbook_parser.blocks import Char, Line, Span
from zh_textbook_parser.semantics import _is_recognize_strip


def annotated_line(text: str, gap: float, size: float = 18.0) -> Line:
    spans = []
    chars = []
    x = 0.0
    for value in text:
        width = size
        bbox = (x, 0.0, x + width, size)
        spans.append(Span(value, bbox, size, "FZKTRJK--GBK1-0"))
        chars.append(Char(value, bbox, size, "FZKTRJK--GBK1-0", "pīn"))
        x += width + gap
    return Line(spans, chars)


class RecognizeStripTest(unittest.TestCase):
    def test_accepts_spaced_annotated_hanzi(self) -> None:
        self.assertTrue(_is_recognize_strip(annotated_line("汽越温滴奔海洋发坏", gap=9.0)))

    def test_rejects_annotated_prose(self) -> None:
        self.assertFalse(_is_recognize_strip(annotated_line("池塘里有一群小蝌蚪", gap=4.0)))

    def test_rejects_lesson_number_and_punctuation(self) -> None:
        self.assertFalse(_is_recognize_strip(annotated_line("1小蝌蚪找妈妈", gap=9.0)))
        self.assertFalse(_is_recognize_strip(annotated_line("你姓什么？", gap=9.0)))


if __name__ == "__main__":
    unittest.main()
