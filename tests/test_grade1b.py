import unittest
from pathlib import Path

from zh_textbook_parser.extract import parse_pages
from zh_textbook_parser.struct import build as build_struct


PDF = Path(__file__).parents[1] / "pdf" / "zh-lang-grade1b-textbook.pdf"


class ReadingCornerTest(unittest.TestCase):
    def test_extracts_both_columns_from_embedded_book(self) -> None:
        lesson = parse_pages(str(PDF), [19])["课文"][0]
        text = lesson["全文"]

        self.assertIsNone(lesson["课号"])
        self.assertEqual(lesson["栏目"], "快乐读书吧")
        self.assertEqual(lesson["标题"], "读读童谣和儿歌")
        self.assertIn("摇摇船", text)
        self.assertIn("还有饼儿还有糕", text)
        self.assertIn("小刺猬理发", text)
        self.assertIn("是个小娃娃", text)
        self.assertLess(text.index("还有饼儿还有糕"), text.index("小刺猬理发"))

    def test_keeps_widely_spaced_text_beside_image_in_lesson(self) -> None:
        lesson = parse_pages(str(PDF), [22])["课文"][0]

        self.assertEqual(lesson["标题"], "吃水不忘挖井人")
        self.assertIn("乡亲们在井旁边立了一块石碑", lesson["全文"])
        self.assertTrue(lesson["全文"].endswith("时刻想念毛主席。”"))

    def test_keeps_annotated_idioms_in_accumulation_section(self) -> None:
        garden = parse_pages(str(PDF), [49], full=True)["页"][0]["园地"]
        section = next(x for x in garden["栏目"] if x["名称"] == "日积月累")
        items = [x["文本"] for x in section["条目"]]

        self.assertEqual(section["生字"], [])
        self.assertEqual(
            items,
            [
                "尊老爱幼",
                "其乐融融",
                "血浓于水",
                "手足情深",
                "同心协力",
                "同甘共苦",
                "天伦之乐",
                "欢聚一堂",
            ],
        )

    def test_merges_unlabelled_adult_reading_continuation_page(self) -> None:
        parsed = parse_pages(str(PDF), [50, 51])
        garden = parsed["语文园地"][0]
        section = next(x for x in garden["栏目"] if x["名称"] == "和大人一起读")
        output = build_struct(parsed)
        output_section = output["园地"][0]["栏目"][0]
        text = output_section["全文"]

        self.assertEqual(garden["页码"], [46, 47])
        self.assertIn("这胖乎乎的小手替我拿过拖鞋呀", text)
        self.assertIn("这胖乎乎的小手帮我挠过痒痒啊", text)
        self.assertTrue(text.endswith("它会帮你们做更多的事情！”"))
        self.assertLess(text.index("全家人都喜欢"), text.index("爸爸说"))
        self.assertNotIn("痒 痒", text)

    def test_places_radical_table_in_appendix_column_order(self) -> None:
        parsed = parse_pages(str(PDF), [124])
        output = build_struct(parsed)
        rows = [x for x in output["附录"] if x["模块"] == "常用偏旁名称表"]

        self.assertEqual(parsed["课文"], [])
        self.assertEqual(len(rows), 34)
        self.assertEqual((rows[0]["序号"], rows[0]["词"]), ("刂", ["立刀旁", "刷别"]))
        self.assertEqual((rows[16]["序号"], rows[16]["词"]), ("攵", ["反文旁", "攻故"]))
        self.assertEqual((rows[17]["序号"], rows[17]["词"]), ("爫", ["爪字头", "爱"]))
        self.assertEqual((rows[-1]["序号"], rows[-1]["词"]), ("雨", ["雨字头", "霜露"]))
        self.assertEqual(output["目录"][-1]["类型"], "附录")
        self.assertEqual(output["目录"][-1]["标题"], "常用偏旁名称表")


if __name__ == "__main__":
    unittest.main()
