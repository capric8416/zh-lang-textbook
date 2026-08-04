import unittest

from zh_textbook_parser.polyphone import _guidance, build


class PolyphoneGuidanceTests(unittest.TestCase):
    def test_grammar_particle_uses_manual_guidance(self):
        context, examples, quick_rule = _guidance("得", "děi", "常用", ["总得"])

        self.assertIn("必须", context)
        self.assertEqual(examples, ["我得走了", "非得完成", "得三天"])
        self.assertIn("需要", quick_rule)

    def test_generic_reading_uses_examples(self):
        context, examples, quick_rule = _guidance(
            "行", "háng", "本册出现", ["银行", "一行"]
        )

        self.assertIn("本册", context)
        self.assertEqual(examples, ["银行", "一行"])
        self.assertIn("háng", quick_rule)

    def test_build_outputs_table_fields(self):
        result = build({"全文": "得到", "拼音": "dé dào"})
        row = next(row for row in result["多音字"] if row["字"] == "得")
        entries = row["本册出现"] + row["常用"] + row["不常用"]

        self.assertTrue(entries)
        self.assertEqual(
            set(entries[0]), {"读音", "语境", "例子", "快速判断"}
        )


if __name__ == "__main__":
    unittest.main()
