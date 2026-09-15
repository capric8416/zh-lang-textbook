import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from zh_native_build.config import BuildConfig
from zh_native_build.stages.onnxruntime import build


class OnnxRuntimeAdapterTest(unittest.TestCase):
    def test_ios_uses_xcode_and_stages_both_header_layouts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = BuildConfig(root=root, target="ios-arm64")
            source = (
                config.speech
                / ".build-deps/sources/onnxruntime-v1.22.0"
            )
            session_include = source / "include/onnxruntime/core/session"
            session_include.mkdir(parents=True)
            for name in ("onnxruntime_c_api.h", "onnxruntime_cxx_api.h"):
                (session_include / name).write_text(f"// {name}\n")

            xcode_output = (
                config.speech
                / ".build-deps/ios-arm64/onnxruntime/Release/Release-iphoneos"
            )
            xcode_output.mkdir(parents=True)
            (xcode_output / "libonnxruntime_common.a").touch()

            with patch("zh_native_build.stages.onnxruntime.run") as run:
                build(config)

            ort_command = [str(part) for part in run.call_args_list[0].args[0]]
            self.assertIn("--cmake_generator", ort_command)
            self.assertEqual(
                ort_command[ort_command.index("--cmake_generator") + 1], "Xcode"
            )
            include = config.speech_vendor / "include"
            self.assertTrue((include / "onnxruntime_cxx_api.h").is_file())
            self.assertTrue(
                (include / "onnxruntime/onnxruntime_cxx_api.h").is_file()
            )


if __name__ == "__main__":
    unittest.main()
