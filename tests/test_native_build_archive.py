import unittest
from pathlib import Path

from zh_native_build.stages.archive import _deduplicate_onnx_archives


class NativeArchiveTest(unittest.TestCase):
    def test_drops_redundant_unix_onnx_proto_archive(self) -> None:
        archives = [
            Path("libonnx.a"),
            Path("libonnx_proto.a"),
            Path("libprotobuf.a"),
        ]

        self.assertEqual(
            _deduplicate_onnx_archives(archives, ".a"),
            [Path("libonnx.a"), Path("libprotobuf.a")],
        )

    def test_drops_redundant_windows_onnx_proto_archive(self) -> None:
        archives = [Path("onnx.lib"), Path("onnx_proto.lib")]

        self.assertEqual(
            _deduplicate_onnx_archives(archives, ".lib"),
            [Path("onnx.lib")],
        )

    def test_keeps_onnx_proto_when_main_archive_is_absent(self) -> None:
        archives = [Path("libonnx_proto.a"), Path("libprotobuf.a")]

        self.assertEqual(_deduplicate_onnx_archives(archives, ".a"), archives)


if __name__ == "__main__":
    unittest.main()
