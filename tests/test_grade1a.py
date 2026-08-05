import unittest
from pathlib import Path

from zh_textbook_parser.extract import parse_pages
from zh_textbook_parser.struct import _lesson_text, _section_text, build


PDF = Path(__file__).parents[1] / "pdf" / "zh-lang-grade1a-textbook.pdf"


class StandaloneTitlePageTest(unittest.TestCase):
    def test_uses_only_large_line_as_title_and_merges_following_page(self) -> None:
        lessons = parse_pages(str(PDF), [6, 7])["课文"]

        self.assertEqual(len(lessons), 1)
        self.assertEqual(lessons[0]["标题"], "我是中国人")
        self.assertEqual(lessons[0]["页码"], [2, 3])
        self.assertEqual(
            lessons[0]["全文"],
            "我是中国人。我们都是中国人。中华民族是一家。",
        )

    def test_separates_numbered_title_from_same_size_body(self) -> None:
        lesson = parse_pages(str(PDF), [13])["课文"][0]

        self.assertEqual(lesson["课号"], "2")
        self.assertIsNone(lesson["课题"])
        self.assertEqual(lesson["标题"], "金木水火土")
        self.assertEqual(
            lesson["全文"],
            "一二三四五，金木水火土。天地分上下，日月照今古。",
        )

    def test_does_not_turn_following_exercise_page_into_lesson(self) -> None:
        parsed = parse_pages(str(PDF), [13, 14])

        self.assertEqual(len(parsed["课文"]), 1)
        self.assertEqual(parsed["课文"][0]["标题"], "金木水火土")
        self.assertEqual(parsed["课文"][0]["页码"], [9])

    def test_keeps_couplet_above_writing_grid_as_lesson_text(self) -> None:
        lesson = parse_pages(str(PDF), [15, 16])["课文"][0]

        self.assertEqual(lesson["标题"], "口耳目手足")
        self.assertEqual(lesson["页码"], [11, 12])
        self.assertEqual(
            lesson["全文"],
            "耳口目手足站如松，坐如钟。行如风，卧如弓。",
        )

    def test_extracts_accumulation_poem_from_garden_continuation(self) -> None:
        parsed = parse_pages(str(PDF), [19, 20])
        garden = parsed["语文园地"][0]
        accumulation = next(
            section for section in garden["栏目"] if section["名称"] == "日积月累"
        )
        poem = accumulation["选文"]

        self.assertEqual(garden["页码"], [15, 16])
        self.assertEqual(poem["标题"], "咏鹅")
        self.assertEqual(poem["作者"], "骆宾王")
        self.assertEqual(poem["年代"], "唐")
        self.assertEqual(
            "".join(unit["文本"] for unit in poem["正文"]),
            "鹅，鹅，鹅，曲项向天歌。白毛浮绿水，红掌拨清波。",
        )
        text, _ = _section_text(accumulation)
        self.assertIn("鹅，鹅，鹅， 曲项向天歌。", text)

    def test_uses_oral_communication_topic_as_title(self) -> None:
        lesson = parse_pages(str(PDF), [21])["课文"][0]

        self.assertEqual(lesson["栏目"], "口语交际")
        self.assertEqual(lesson["标题"], "我说你做")
        self.assertTrue(lesson["全文"].startswith("我们一起来做游戏吧！"))
        self.assertIn("请你抬起一条腿。", lesson["全文"])
        self.assertIn("别人说话时要认真听。", lesson["全文"])

    def test_restores_crossed_friend_dialogue_bubbles(self) -> None:
        lesson = parse_pages(str(PDF), [74])["课文"][0]
        text, pinyin = _lesson_text(lesson)

        self.assertEqual(lesson["标题"], "交朋友")
        self.assertIn(
            "我喜欢跳绳。你呢？我也喜欢。放学后我们一起去跳绳吧！好啊！",
            text,
        )
        self.assertNotIn("放学后我喜欢跳绳", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_keeps_after_class_example_out_of_lesson_and_reads_author_note(self) -> None:
        parsed = parse_pages(str(PDF), [88, 89])
        lesson = parsed["课文"][0]
        text, pinyin = _lesson_text(lesson)

        self.assertEqual(lesson["标题"], "小小的船")
        self.assertEqual(lesson["作者"], "叶圣陶")
        self.assertEqual(lesson["页码"], [84])
        self.assertEqual(
            text,
            "弯弯的月儿小小的船，小小的船儿两头尖。"
            "我在小小的船里坐，只看见闪闪的星星蓝蓝的天。",
        )
        self.assertNotIn("星星闪闪的星星天蓝蓝的天", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_ignores_oversized_image_placeholder_on_oral_page(self) -> None:
        lesson = parse_pages(str(PDF), [107])["课文"][0]

        self.assertEqual(lesson["栏目"], "口语交际")
        self.assertEqual(lesson["标题"], "我会想办法")
        self.assertNotIn("?", lesson["全文"])

    def test_keeps_reading_corner_speech_bubbles_separate(self) -> None:
        lesson = parse_pages(str(PDF), [23])["课文"][0]

        self.assertEqual(lesson["标题"], "读书真快乐")
        self.assertEqual(
            lesson["全文"],
            "我经常和爸爸妈妈一起读有趣的故事书。"
            "我读了很多书，会讲很多故事，同学们叫我“故事大王”。"
            "周末，我在书店看到了很多好看的图画书。"
            "学了拼音，我就可以认更多的字，读更多的书了！",
        )
        self.assertEqual(sorted({unit["段落"] for unit in lesson["正文"]}), [1, 2, 3, 4])

    def test_keeps_read_aloud_selection_below_recognize_strip(self) -> None:
        lesson = parse_pages(str(PDF), [30, 31])["课文"][0]
        text, _ = _lesson_text(lesson)

        self.assertEqual(lesson["标题"], "ddttnnll")
        self.assertIn("读一读。", lesson["全文"])
        self.assertIn("小白兔，穿皮袄，", lesson["全文"])
        self.assertIn(" 读一读。 小白兔① ", text)

    def test_separates_pinyin_drills_from_hanzi_words(self) -> None:
        bpmf = parse_pages(str(PDF), [29])["课文"][0]
        dtnl = parse_pages(str(PDF), [30, 31])["课文"][0]
        bpmf_text, bpmf_pinyin = _lesson_text(bpmf)
        dtnl_text, dtnl_pinyin = _lesson_text(dtnl)

        self.assertIn("f爸爸", bpmf["全文"])
        self.assertIn("f 爸爸", bpmf_text)
        self.assertIn("lǘ 大地", dtnl_text)
        self.assertEqual(len(bpmf_text), len(bpmf_pinyin.split(" ")))
        self.assertEqual(len(dtnl_text), len(dtnl_pinyin.split(" ")))

    def test_formats_pinyin_practice_as_separate_garden_section(self) -> None:
        garden = parse_pages(str(PDF), [32, 33])["语文园地"][0]
        practice = next(section for section in garden["栏目"] if section["名称"] == "用拼音")
        station = next(section for section in garden["栏目"] if section["名称"] == "识字加油站")
        text, pinyin = _section_text(practice)
        station_text, _ = _section_text(station)

        self.assertNotIn("九九九", station_text)
        self.assertNotIn("王王王", station_text)
        self.assertIn("读一读，读准声调。", text)
        self.assertIn("dǎ—dà\u2005mō—mǒ\u2005bí—bǐ\u2005pǔ—pù", text)
        self.assertIn("比一比，读一读。", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

        matching = next(
            section for section in garden["栏目"] if section["名称"] == "字词句运用"
        )
        matching_text, matching_pinyin = _section_text(matching)
        self.assertIn("读一读，连一连。", matching_text)
        self.assertIn("他\u2005八\u2005马　u", matching_text)
        self.assertIn("七\u2005地\u2005你　a", matching_text)
        self.assertIn("目\u2005土\u2005足　i", matching_text)
        self.assertIn("我还会说：妈、爸、大……", matching_text)
        self.assertEqual(len(matching_text), len(matching_pinyin.split(" ")))

    def test_parses_adult_reading_start_and_merges_continuation(self) -> None:
        parsed = parse_pages(str(PDF), [33, 34, 35])
        lesson = parsed["课文"][0]

        self.assertEqual(lesson["栏目"], "和大人一起读")
        self.assertEqual(lesson["标题"], "小白兔和小灰兔")
        self.assertEqual(lesson["页码"], [30, 31])
        self.assertTrue(lesson["全文"].startswith("老山羊在地里收白菜"))
        self.assertTrue(lesson["全文"].endswith("才有吃不完的菜。”"))

    def test_formats_course_schedule_as_aligned_text_rows(self) -> None:
        garden = parse_pages(str(PDF), [46])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "识字加油站"
        )
        text, pinyin = _section_text(section)

        self.assertIn("星期一　星期二　星期三　星期四　星期五", text)
        self.assertIn("第一节　语文　语文　数学　语文　数学", text)
        self.assertIn("第三节　道德与法治　语文　体育与健康　科学　体育与健康", text)
        self.assertIn("第五节　美术　综合实践活动　道德与法治　体育与健康　班会", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_formats_picture_finding_words_as_rows(self) -> None:
        garden = parse_pages(str(PDF), [46, 47])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "字词句运用"
        )
        text, pinyin = _section_text(section)

        self.assertIn("读一读，在图里找一找。", text)
        self.assertIn("鸡　鱼　河", text)
        self.assertIn("一座山　一棵树", text)
        self.assertIn("四只鸽子　七朵花", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_formats_time_words_as_three_aligned_rows(self) -> None:
        garden = parse_pages(str(PDF), [60, 61])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "识字加油站"
        )
        text, pinyin = _section_text(section)

        self.assertEqual(
            text,
            "上午　昨天　上个月　去年 "
            "下午　今天　这个月　今年 "
            "晚上　明天　下个月　明年",
        )
        self.assertNotIn("日", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_formats_word_expansion_and_restores_writing_words(self) -> None:
        garden = parse_pages(str(PDF), [62])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "字词句运用"
        )
        text, pinyin = _section_text(section)

        self.assertEqual(
            text,
            "读一读，说一说。 车 火车　马车　汽车 "
            "上车　坐车　车站　车厢 拼一拼，写一写。 门口　生日　题目　田野",
        )
        self.assertEqual(
            pinyin.split(" ")[-11:],
            ["mén", "kǒu", "", "shēng", "rì", "", "tí", "mù", "", "tián", "yě"],
        )
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_extracts_and_exposes_jiangnan_source(self) -> None:
        parsed = parse_pages(str(PDF), [66])
        lesson = parsed["课文"][0]

        self.assertEqual(lesson["标题"], "江南")
        self.assertIsNone(lesson["作者"])
        self.assertEqual(lesson["出处"], "汉乐府")
        self.assertEqual(build(parsed)["课文"][0]["出处"], "汉乐府")

    def test_formats_and_restores_opposite_word_pairs(self) -> None:
        garden = parse_pages(str(PDF), [72])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "识字加油站"
        )
        text, pinyin = _section_text(section)

        self.assertEqual(
            text,
            "南—北　男—女　开—关 正—反　先—后　内—外 "
            "我也会说这样的词语……",
        )
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_formats_season_words_and_keeps_continuation(self) -> None:
        garden = parse_pages(str(PDF), [72, 73])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "字词句运用"
        )
        text, pinyin = _section_text(section)

        self.assertTrue(
            text.startswith(
                "读一读，说一说。 春天　夏天　秋天　冬天 "
                "大地　树叶　青草　莲花 飞鸟　小鱼　青蛙　雪人 "
                "我最喜欢冬天，因为冬天可以堆雪人……"
            )
        )
        self.assertIn("你认识哪些同学的名字？是怎么认识的？", text)
        self.assertIn("和同学交流。", text)
        self.assertIn("这些卡片上的名字我都认识。", text)
        self.assertIn("我从写字本上认识了一些同学的名字。", text)
        self.assertIn("一年级（3）班　刘丽", text)
        self.assertIn("李晓宇　6岁", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_merges_and_formats_garden_six_continuation(self) -> None:
        parsed = parse_pages(str(PDF), [84, 85])
        garden = parsed["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "字词句运用"
        )
        text, pinyin = _section_text(section)

        self.assertEqual(parsed["课文"], [])
        self.assertEqual(garden["页码"], [80, 81])
        self.assertIn("读一读，读准字音。", text)
        self.assertIn("你们　家里　男生　蓝色", text)
        self.assertIn("上山　三年　写字　报纸", text)
        self.assertIn("读一读，和同学交流你的发现。", text)
        self.assertIn("树　林　桃　桥", text)
        self.assertIn("花　草　莲　菜", text)
        self.assertIn("很多木字旁的字都和树木有关。", text)
        self.assertIn("“桥”字为什么和树木有关呢？我想问问老师。", text)
        self.assertIn("你在路上认识了哪些字？和同学交流。", text)
        self.assertIn("看图写词语，再说一两句话。", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_formats_garden_seven_comparison_and_discovery(self) -> None:
        parsed = parse_pages(str(PDF), [94, 95])
        garden = parsed["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "字词句运用"
        )
        text, pinyin = _section_text(section)

        self.assertEqual(garden["页码"], [90, 91])
        self.assertIn("比一比，写一写。", text)
        self.assertIn("了　才　云　山", text)
        self.assertIn("儿　四　我　心", text)
        self.assertIn("读一读，和同学交流你的发现。", text)
        self.assertIn("明　晚　昨　春", text)
        self.assertIn("妈　奶　姐　妹", text)
        self.assertIn("这几个字的意思都和时间有关。", text)
        self.assertIn("读一读，背一背。", text)
        self.assertIn("早晨起来，面向太阳。", text)
        self.assertIn("前面是东，后面是西。", text)
        self.assertIn("左面是北，右面是南。", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_formats_garden_eight_character_structure_activity(self) -> None:
        garden = parse_pages(str(PDF), [105])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "识字加油站"
        )
        text, pinyin = _section_text(section)

        self.assertEqual(
            text,
            "连一连。 牛　羊　只　爪　叶 花　田　作 "
            "元　拼　音　巴　白 有些字可以分成上下两部分。",
        )
        self.assertNotIn("花　口　作", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_formats_garden_eight_paired_words_and_keeps_prompt(self) -> None:
        garden = parse_pages(str(PDF), [105, 106])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "字词句运用"
        )
        text, pinyin = _section_text(section)

        self.assertEqual(
            text,
            "读一读。 果皮　树皮　加法　办法　回来　回答 "
            "许多　不许　到处　四处　方向　地方 "
            "新年快到了，给家人或朋友写一句祝福的话吧！",
        )
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_formats_garden_eight_writing_hints(self) -> None:
        garden = parse_pages(str(PDF), [105, 106])["语文园地"][0]
        section = next(
            item for item in garden["栏目"] if item["名称"] == "书写提示"
        )
        text, pinyin = _section_text(section)

        self.assertEqual(
            text,
            "笔顺规则：先外后内。 月　风 "
            "笔顺规则：先中间后两边。 小　水",
        )
        self.assertNotIn("小小小", text)
        self.assertEqual(len(text), len(pinyin.split(" ")))

    def test_keeps_appendix_group_heading_out_of_previous_row(self) -> None:
        appendix = parse_pages(str(PDF), [109, 110, 111])["附录"][0]
        group_names = [group["名称"] for group in appendix["分组"]]

        self.assertIn("识字", group_names)
        self.assertIn("阅读", group_names)
        garden_five = next(
            row
            for group in appendix["分组"]
            for row in group["行"]
            if row["标签"] == "语文园地五"
        )
        text = "".join(item["字"] for item in garden_five["内容"])
        self.assertEqual(text, "男女关正反先后内外")
        self.assertNotIn("识字", text)
        garden_eight = next(
            row
            for group in appendix["分组"]
            for row in group["行"]
            if row["标签"] == "语文园地八"
        )
        self.assertEqual(
            "".join(item["字"] for item in garden_eight["内容"]),
            "牛羊爪元拼音",
        )

    def test_reads_writing_table_by_column(self) -> None:
        appendix = parse_pages(str(PDF), [112])["附录"][0]
        rows = [row for group in appendix["分组"] for row in group["行"]]

        garden_one = next(row for row in rows if row["标签"] == "语文园地一")
        garden_six = next(row for row in rows if row["标签"] == "语文园地六")
        self.assertEqual(garden_one["内容"], list("六七八十"))
        self.assertEqual(garden_six["内容"], list("工厂门卫"))
        self.assertNotIn("语文园地六", "".join(garden_one["内容"]))
        garden_eight = next(row for row in rows if row["标签"] == "语文园地八")
        self.assertEqual(garden_eight["内容"], list("牛羊爪白"))

    def test_parses_stroke_and_radical_tables_as_final_appendices(self) -> None:
        appendices = parse_pages(str(PDF), [113, 114])["附录"]

        self.assertEqual(
            [table["名称"] for table in appendices],
            ["笔画名称表", "常用偏旁名称表"],
        )
        stroke_rows = appendices[0]["分组"][0]["行"]
        radical_rows = appendices[1]["分组"][0]["行"]
        self.assertEqual(stroke_rows[0]["内容"], ["㇐", "横", "一十"])
        self.assertEqual(stroke_rows[-1]["内容"], ["㇎", "横折折折钩", "奶"])
        self.assertEqual(len(stroke_rows), 32)
        self.assertEqual(len(radical_rows), 29)
        self.assertIn(["亻", "单人旁", "作件"], [row["内容"] for row in radical_rows])
        self.assertIn(["竹", "竹字头", "笔答"], [row["内容"] for row in radical_rows])


if __name__ == "__main__":
    unittest.main()
