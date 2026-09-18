import unittest

from scripts.generate_reviewed_textbook import SourceText


class ReviewedTextbookGenerationTest(unittest.TestCase):
    def test_removes_footnote_marks_and_preceding_whitespace_with_pinyin(self) -> None:
        text = "左边 \t②右边① 结尾"
        pinyin = " ".join(f"p{index}" for index in range(len(text)))

        source = SourceText.from_json(text, pinyin)

        self.assertEqual(source.text, "左边右边 结尾")
        self.assertEqual(
            source.syllables,
            ("p0", "p1", "p5", "p6", "p8", "p9", "p10"),
        )


if __name__ == "__main__":
    unittest.main()
