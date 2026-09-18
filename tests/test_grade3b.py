from pathlib import Path
import unittest

from zh_textbook_parser.extract import parse_pages


PDF = Path(__file__).parents[1] / "pdf" / "zh-lang-grade3b-textbook.pdf"


class Grade3bSectionTest(unittest.TestCase):
    def test_oral_and_composition_pages_do_not_inherit_previous_lesson(self) -> None:
        parsed = parse_pages(str(PDF), [15, 16], full=True)
        oral, composition = (page["课文"] for page in parsed["页"])

        self.assertEqual(
            (oral["课号"], oral["栏目"], oral["标题"]),
            (None, "口语交际", "春游去哪里"),
        )
        self.assertEqual(
            (composition["课号"], composition["栏目"], composition["标题"]),
            (None, "习作", "我的植物朋友"),
        )

    def test_after_class_recognition_strip_is_not_a_lesson(self) -> None:
        parsed = parse_pages(str(PDF), [90], full=True)

        self.assertIsNone(parsed["页"][0]["课文"])


if __name__ == "__main__":
    unittest.main()
