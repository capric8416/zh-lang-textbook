import unittest

from zh_textbook_parser.merge import _append_content


class CrossPagePinyinTest(unittest.TestCase):
    def test_offsets_pinyin_positions_when_joining_open_sentence(self) -> None:
        out = {
            "正文": [
                {
                    "文本": "他们后",
                    "字数": 3,
                    "段落": 1,
                    "跨页续句": True,
                    "注音": [{"字": "后", "拼音": "hòu", "序": 2}],
                    "位置": [],
                }
            ]
        }
        page = {
            "页码": 2,
            "pdf页序": 7,
            "课文": {
                "首行缩进": False,
                "正文": [
                    {
                        "文本": "腿一蹬，",
                        "字数": 4,
                        "段落": 1,
                        "注音": [
                            {"字": "腿", "拼音": "tuǐ", "序": 0},
                            {"字": "一", "拼音": "yì", "序": 1},
                            {"字": "蹬", "拼音": "dēng", "序": 2},
                        ],
                        "bbox": [0, 0, 10, 10],
                    }
                ],
            },
        }

        _append_content(out, page)

        self.assertEqual(out["正文"][0]["文本"], "他们后腿一蹬，")
        self.assertEqual(
            [item["序"] for item in out["正文"][0]["注音"]], [2, 3, 4, 5]
        )


if __name__ == "__main__":
    unittest.main()
