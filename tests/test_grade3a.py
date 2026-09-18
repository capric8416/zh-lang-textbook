import unittest
from pathlib import Path

from zh_textbook_parser.extract import parse_pages
from zh_textbook_parser.struct import build as build_struct


PDF = Path(__file__).parents[1] / "pdf" / "zh-lang-grade3a-textbook.pdf"


class Grade3aUnitAndGardenTest(unittest.TestCase):
    def test_body_unit_opener_sets_unit_without_becoming_lesson(self) -> None:
        parsed = parse_pages(str(PDF), [5, 6])

        self.assertEqual(len(parsed["课文"]), 1)
        self.assertEqual(parsed["课文"][0]["课号"], "1")
        self.assertEqual(parsed["课文"][0]["单元"]["单元"], 1)

    def test_bare_garden_title_stops_before_next_unit_opener(self) -> None:
        parsed = parse_pages(str(PDF), list(range(5, 19)))

        self.assertEqual(len(parsed["语文园地"]), 1)
        self.assertEqual(parsed["语文园地"][0]["标题"], "语文园地")
        self.assertEqual(parsed["语文园地"][0]["页码"], [11, 12])
        self.assertEqual(parsed["语文园地"][0]["单元"]["单元"], 1)
        lesson_four = next(item for item in parsed["课文"] if item["课号"] == "4")
        self.assertEqual(lesson_four["单元"]["单元"], 2)

    def test_poem_note_pages_are_kept_in_the_numbered_lesson(self) -> None:
        parsed = build_struct(parse_pages(str(PDF), [88, 89]))

        lesson = next(item for item in parsed["课文"] if item["课号"] == "20")
        self.assertIn("欲把西湖比西子", lesson["全文"])
        self.assertNotIn("饮湖上初晴后雨注释", [item["标题"] for item in parsed["课文"]])


if __name__ == "__main__":
    unittest.main()
