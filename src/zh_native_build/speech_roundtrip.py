from __future__ import annotations

import argparse
import ctypes
import re
import sys
from dataclasses import dataclass
from contextlib import ExitStack
from pathlib import Path

from pypinyin import Style, lazy_pinyin


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
DEFAULT_LIBRARY = APP / "native" / "speech" / "build-linux" / "libzh_speech.so"
DEFAULT_TTS = APP / "assets" / "speech" / "piper-zh_CN-xiao_ya-medium"
DEFAULT_ASR = APP / "assets" / "speech" / "funasr-paraformer-zh"
DEFAULT_VAD = APP / "assets" / "speech" / "funasr-fsmn-vad"
DEFAULT_OUTPUT = APP / "build" / "speech-roundtrip"
DEFAULT_SAMPLES = ("春天", "今天天气很好。")


@dataclass(frozen=True)
class NativeFunctions:
    tts_create: object
    tts_destroy: object
    synthesize: object
    asr_create: object
    asr_destroy: object
    recognize: object


def hanzi_to_numeric_pinyin(text: str) -> list[str]:
    """Return numbered pinyin syllables, ignoring punctuation and other symbols."""
    syllables = lazy_pinyin(
        text,
        style=Style.TONE3,
        neutral_tone_with_five=True,
        errors=lambda _: [],
    )
    return [syllable.lower().replace("u:", "v").replace("ü", "v") for syllable in syllables]


def load_native(library_path: Path) -> tuple[ctypes.CDLL, NativeFunctions]:
    library = ctypes.CDLL(str(library_path))

    library.zh_speech_tts_create.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    library.zh_speech_tts_create.restype = ctypes.c_void_p
    library.zh_speech_tts_destroy.argtypes = [ctypes.c_void_p]
    library.zh_speech_tts_destroy.restype = None
    library.zh_speech_tts_synthesize_wav.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_float,
        ctypes.c_int32,
    ]
    library.zh_speech_tts_synthesize_wav.restype = ctypes.c_int32

    library.zh_speech_asr_create.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    library.zh_speech_asr_create.restype = ctypes.c_void_p
    library.zh_speech_asr_destroy.argtypes = [ctypes.c_void_p]
    library.zh_speech_asr_destroy.restype = None
    library.zh_speech_asr_recognize_wav.argtypes = [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_int32,
    ]
    library.zh_speech_asr_recognize_wav.restype = ctypes.c_int32

    return library, NativeFunctions(
        tts_create=library.zh_speech_tts_create,
        tts_destroy=library.zh_speech_tts_destroy,
        synthesize=library.zh_speech_tts_synthesize_wav,
        asr_create=library.zh_speech_asr_create,
        asr_destroy=library.zh_speech_asr_destroy,
        recognize=library.zh_speech_asr_recognize_wav,
    )


def require_path(path: Path, description: str) -> Path:
    resolved = path.expanduser().resolve()
    if not resolved.exists():
        raise FileNotFoundError(f"{description}不存在: {resolved}")
    return resolved


def safe_filename(index: int, text: str) -> str:
    stem = re.sub(r"[^\w\u3400-\u9fff]+", "-", text, flags=re.UNICODE).strip("-")
    return f"{index:02d}-{stem or 'sample'}.wav"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="用原生 Piper 生成语音，再用 FunASR 识别并比较汉字拼音。"
    )
    parser.add_argument(
        "texts",
        nargs="*",
        help="待测试的词语或句子；不传时测试“春天”和“今天天气很好。”",
    )
    parser.add_argument("--library", type=Path, default=DEFAULT_LIBRARY)
    parser.add_argument(
        "--offline-library", type=Path,
        help="额外加载使用 FunOffline API 编译的测试库，与原接口识别同一份 WAV",
    )
    parser.add_argument("--tts-model-dir", type=Path, default=DEFAULT_TTS)
    parser.add_argument("--asr-model-dir", type=Path, default=DEFAULT_ASR)
    parser.add_argument("--vad-model-dir", type=Path, default=DEFAULT_VAD)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def check_recognition(native, handle, label: str, text: str,
                      expected: list[str], wav_path: Path) -> bool:
    output = ctypes.create_string_buffer(64 * 1024)
    status = native.recognize(handle, str(wav_path).encode(), output, len(output))
    if status < 0:
        reason = {
            -1: "参数无效", -2: "VAD 推理失败", -3: "未检测到语音",
            -4: "ASR 推理失败", -5: "原生异常",
        }.get(status, "未知错误")
        print(f"[FAIL][{label}] {text!r}: {reason}（错误码 {status}）", flush=True)
        return False
    if status >= len(output):
        print(f"[FAIL][{label}] {text!r}: 识别结果超出缓冲区", flush=True)
        return False
    recognized = output.value.decode("utf-8", errors="replace")
    actual = hanzi_to_numeric_pinyin(recognized)
    matched = bool(recognized.strip()) and expected == actual
    print(f"[{'PASS' if matched else 'FAIL'}][{label}] {text}")
    print(f"       输入拼音: {' '.join(expected)}")
    print(f"       识别汉字: {recognized or '<空：接口返回 0 字节>'}")
    print(f"       识别拼音: {' '.join(actual) or '<空>'}")
    print(f"       WAV: {wav_path}", flush=True)
    return matched


def run() -> int:
    args = parse_args()
    texts = args.texts or list(DEFAULT_SAMPLES)

    try:
        library_path = require_path(args.library, "原生语音库")
        tts_dir = require_path(args.tts_model_dir, "TTS 模型目录")
        asr_dir = require_path(args.asr_model_dir, "ASR 模型目录")
        vad_dir = require_path(args.vad_model_dir, "VAD 模型目录")
        tts_model = require_path(tts_dir / "model.onnx", "TTS 模型")
        tts_config = require_path(tts_dir / "model.onnx.json", "TTS 配置")
        _, native = load_native(library_path)
        groups = [("FunOfflineInfer", native)]
        if args.offline_library:
            offline_path = require_path(args.offline_library, "FunOffline 测试库")
            if offline_path == library_path:
                raise ValueError("原接口库与 FunOffline 测试库必须是不同文件")
            _, offline_native = load_native(offline_path)
            groups.append(("FunOfflineInfer", offline_native))
    except (OSError, AttributeError, ValueError) as error:
        print(f"[ERROR] 初始化失败: {error}", file=sys.stderr)
        return 2

    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    tts_handle = native.tts_create(str(tts_model).encode(), str(tts_config).encode())
    if not tts_handle:
        print("[ERROR] TTS 初始化失败", file=sys.stderr)
        return 2

    with ExitStack() as cleanup:
        cleanup.callback(native.tts_destroy, tts_handle)
        recognizers = []
        for label, functions in groups:
            handle = functions.asr_create(str(asr_dir).encode(), str(vad_dir).encode())
            if not handle:
                print(f"[ERROR][{label}] ASR/VAD 初始化失败", file=sys.stderr)
                return 2
            cleanup.callback(functions.asr_destroy, handle)
            recognizers.append((label, functions, handle))

        passes = {label: 0 for label, _ in groups}
        for index, text in enumerate(texts, start=1):
            expected = hanzi_to_numeric_pinyin(text)
            if not expected:
                print(f"[FAIL] {text!r}: 没有可测试的汉字")
                continue

            wav_path = output_dir / safe_filename(index, text)
            numeric_pinyin = " ".join(expected)
            length_scale = 0.8 if len(expected) > 2 else 1.25
            status = native.synthesize(
                tts_handle,
                numeric_pinyin.encode(),
                str(wav_path).encode(),
                ctypes.c_float(length_scale),
                1,
            )
            if status != 0:
                print(f"[FAIL] {text!r}: TTS 生成失败（错误码 {status}）")
                continue

            for label, functions, handle in recognizers:
                passes[label] += check_recognition(
                    functions, handle, label, text, expected, wav_path
                )

        for label, count in passes.items():
            print(f"结果 [{label}]: {count}/{len(texts)} 通过", flush=True)
        # Preserve failing control results in the exit status, even when the
        # new API passes. This is a diagnostic comparison, not a known-fail skip.
        return int(any(count != len(texts) for count in passes.values()))


if __name__ == "__main__":
    raise SystemExit(run())
