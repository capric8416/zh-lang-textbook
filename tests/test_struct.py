import unittest

from zh_textbook_parser.struct import _lesson_text, annotate


class SourceFirstPinyinTest(unittest.TestCase):
    def test_reviewed_tone_sandhi_for_yiqilai(self) -> None:
        self.assertEqual(annotate("一起来"), "yì qǐ lái")

    def test_annotate_preserves_source_and_fills_missing_pinyin(self) -> None:
        text = "似剪刀。"
        result = annotate(text, {0: "shì"})

        self.assertEqual(result.split(" "), ["shì", "jiǎn", "dāo", "。"])

    def test_lesson_text_preserves_source_positions(self) -> None:
        lesson = {
            "正文": [
                {
                    "文本": "小蝌蚪，",
                    "注音": [
                        {"字": "小", "拼音": "xiǎo", "序": 0},
                        {"字": "蝌", "拼音": "kē", "序": 1},
                    ],
                },
                {
                    "文本": "游。",
                    "注音": [{"字": "游", "拼音": "yóu", "序": 0}],
                },
            ]
        }

        text, result = _lesson_text(lesson)

        self.assertEqual(text, "小蝌蚪，游。")
        self.assertEqual(
            result.split(" "), ["xiǎo", "kē", "dǒu", "，", "yóu", "。"]
        )

    def test_reviewed_phrase_correction_overrides_old_source_reading(self) -> None:
        result = annotate("不要着急", {0: "bù", 2: "zhe"})

        self.assertEqual(result.split(" "), ["bú", "yào", "zháo", "jí"])


if __name__ == "__main__":
    unittest.main()
