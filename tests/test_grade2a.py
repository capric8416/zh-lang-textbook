import unittest
from pathlib import Path

from zh_textbook_parser.extract import parse_page, parse_pages

import fitz


PDF = Path(__file__).parents[1] / "pdf" / "zh-lang-grade2a-textbook.pdf"


class IllustratedLessonTest(unittest.TestCase):
    def test_keeps_spaced_paragraph_before_multiline_recognize_strip(self) -> None:
        lesson = parse_pages(str(PDF), [5, 6, 7])["课文"][0]

        self.assertEqual(lesson["标题"], "小蝌蚪找妈妈")
        self.assertIn("不知什么时候，小青蛙的尾巴已经不见了", lesson["全文"])
        self.assertTrue(lesson["全文"].endswith("他们跟着妈妈，天天去捉害虫。"))

        with fitz.open(PDF) as doc:
            page = parse_page(doc, 7, full=True)
        self.assertEqual(
            [x["字"] for x in page["课后"]["生字"]["会认"]],
            list("蝌蚪脑袋灰甩活腿教迎嘴龟披蹲肚鼓"),
        )

    def test_uses_reading_corner_main_title(self) -> None:
        lesson = parse_pages(str(PDF), [19])["课文"][0]

        self.assertIsNone(lesson["课号"])
        self.assertEqual(lesson["栏目"], "快乐读书吧")
        self.assertEqual(lesson["标题"], "读读童话故事")
        self.assertTrue(lesson["全文"].startswith("来吧，插上想象的翅膀"))
        self.assertTrue(lesson["全文"].endswith("我们一起来读一读。"))
        self.assertNotIn("每天读20分钟", lesson["全文"])
