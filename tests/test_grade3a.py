import unittest
from pathlib import Path

from zh_textbook_parser.extract import parse_pages


PDF = Path(__file__).parents[1] / "pdf" / "zh-lang-grade3a-textbook.pdf"


class Grade3aUnitAndGardenTest(unittest.TestCase):
    def test_body_unit_opener_sets_unit_without_becoming_lesson(self) -> None:
        parsed = parse_pages(str(PDF), [5, 6])

        self.assertEqual(len(parsed["课文"]), 1)
        self.assertEqual(parsed["课文"][0]["课号"], "1")
        self.assertEqual(parsed["课文"][0]["单元"]["单元"], 1)

    def test_bare_garden_title_stops_before_next_unit_opener(self) -> None:
        parsed = parse_pages(str(PDF), [15, 16, 17, 18])

        self.assertEqual(len(parsed["语文园地"]), 1)
        self.assertEqual(parsed["语文园地"][0]["标题"], "语文园地")
        self.assertEqual(parsed["语文园地"][0]["页码"], [11, 12])
        self.assertEqual(parsed["语文园地"][0]["单元"]["单元"], 1)
        self.assertEqual(parsed["课文"][0]["课号"], "4")
        self.assertEqual(parsed["课文"][0]["单元"]["单元"], 2)


if __name__ == "__main__":
    unittest.main()
