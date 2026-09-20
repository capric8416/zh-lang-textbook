import unittest
from pathlib import Path

from scripts.generate_reviewed_textbook import generate
from zh_textbook_parser.extract import parse_pages
from zh_textbook_parser.struct import build as build_struct


PDF = Path(__file__).parents[1] / "pdf" / "zh-lang-grade3a-textbook.pdf"
REVIEWED = (
    Path(__file__).parents[1]
    / "json_reviewed"
    / "zh-lang-grade3a-textbook-struct.json"
)


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

    def test_three_poems_are_rebuilt_without_inline_notes(self) -> None:
        parsed = build_struct(parse_pages(str(PDF), list(range(5, 21))))
        lesson = next(item for item in parsed["课文"] if item["课号"] == "4")

        self.assertNotIn("注释", lesson["全文"])
        self.assertNotIn("篱笆", lesson["全文"])
        self.assertEqual(
            lesson["全文"].splitlines(),
            [
                "望洞庭",
                "湖光秋月两相和，",
                "潭面无风镜未磨。",
                "遥望洞庭山水翠，",
                "白银盘里一青螺。",
                "山行",
                "远上寒山石径斜，",
                "白云生处有人家。",
                "停车坐爱枫林晚，",
                "霜叶红于二月花。",
                "夜书所见",
                "萧萧梧叶送寒声，",
                "江上秋风动客情。",
                "知有儿童挑促织，",
                "夜深篱落一灯明。",
            ],
        )

    def test_garden_poems_have_independent_author_and_dynasty_nodes(self) -> None:
        reviewed = generate(REVIEWED)
        expected = {
            "u01-garden": ("所见", "袁枚", "清"),
            "u02-garden": ("舟夜书所见", "查慎行", "清"),
            "u06-garden": ("早发白帝城", "李白", "唐"),
            "u07-garden": ("采莲曲", "王昌龄", "唐"),
        }
        gardens = {
            chapter["id"]: chapter
            for unit in reviewed["contents"]
            for chapter in unit["chapters"]
            if chapter.get("content_type") == "garden"
        }
        for garden_id, (title, author, dynasty) in expected.items():
            poem = next(
                child
                for child in gardens[garden_id]["children"]
                if child["content_type"] == "poem"
            )
            self.assertEqual(poem["title"]["zh"], title)
            self.assertEqual(poem["author"]["zh"], author)
            self.assertEqual(poem["dynasty"]["zh"], dynasty)
            self.assertNotIn(author, "".join(row["zh"] for row in poem["text"]))

    def test_three_poem_lesson_uses_independent_children(self) -> None:
        reviewed = generate(REVIEWED)
        chapter = next(
            chapter
            for unit in reviewed["contents"]
            for chapter in unit["chapters"]
            if chapter.get("id") == "u02-reading-04"
        )
        self.assertEqual(chapter["name"], "古诗三首")
        self.assertEqual(chapter["content_type"], "collection")
        self.assertNotIn("topic", chapter)
        self.assertEqual(
            {child["topic"]["zh"] for child in chapter["children"]},
            {"古诗三首"},
        )
        self.assertEqual(
            [
                (child["title"]["zh"], child["author"]["zh"], child["dynasty"]["zh"])
                for child in chapter["children"]
            ],
            [("望洞庭", "刘禹锡", "唐"), ("山行", "杜牧", "唐"), ("夜书所见", "叶绍翁", "宋")],
        )
        self.assertEqual(
            [len(child["text"]) for child in chapter["children"]], [4, 4, 4]
        )
        self.assertEqual(
            [child["text"][0]["zh"] for child in chapter["children"]],
            ["湖光秋月两相和，", "远上寒山石径斜，", "萧萧梧叶送寒声，"],
        )

    def test_writing_section_is_a_unit_level_work(self) -> None:
        reviewed = generate(REVIEWED)
        writing = next(
            chapter
            for unit in reviewed["contents"]
            for chapter in unit["chapters"]
            if chapter.get("id") == "u02-writing-01"
        )
        self.assertEqual(writing["name"], "写日记")
        self.assertEqual(writing["content_type"], "writing")
        self.assertEqual(writing["title"]["zh"], "写日记")
        self.assertIn("牙齿", "".join(item["zh"] for item in writing["text"]))


if __name__ == "__main__":
    unittest.main()
