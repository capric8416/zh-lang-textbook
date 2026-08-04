import unittest
from pathlib import Path

from zh_textbook_parser.extract import parse_page, parse_pages
from zh_textbook_parser.struct import build as build_struct

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

    def test_keeps_sparse_paragraph_wrapped_beside_illustration(self) -> None:
        lesson = parse_pages(str(PDF), [79, 80])["课文"][0]

        self.assertEqual(lesson["标题"], "刘胡兰")
        self.assertTrue(
            lesson["全文"].endswith(
                "毛主席听到这个消息，亲笔为她题词：“生的伟大，死的光荣。”"
            )
        )

    def test_keeps_matching_exercise_rows_together(self) -> None:
        parsed = parse_pages(str(PDF), [82])
        section = next(
            item
            for item in parsed["语文园地"][0]["栏目"]
            if item["名称"] == "识字加油站"
        )
        rows = [item["文本"] for item in section["条目"]]

        self.assertEqual(
            rows[1:4],
            [
                "山（ ）\u2005锋　爆（ ）\u2005吵　幕\u2005（ ）名",
                "蜜（ ）\u2005峰　争（ ）\u2005抄　墓\u2005（ ）地",
                "刀（ ）\u2005蜂　摘（ ）\u2005炒　慕\u2005（ ）布",
            ],
        )

        output = build_struct(parsed)
        rendered = next(
            item
            for item in output["园地"][0]["栏目"]
            if item["名称"] == "识字加油站"
        )
        tokens = rendered["拼音"].split(" ")
        placeholders = [
            i
            for i, char in enumerate(rendered["全文"])
            if char == " " and i > 0 and rendered["全文"][i - 1] == "（"
        ]
        self.assertEqual(
            [tokens[i] for i in placeholders],
            ["fēng", "chǎo", "mù", "fēng", "chǎo", "mù", "fēng", "chāo", "mù"],
        )
