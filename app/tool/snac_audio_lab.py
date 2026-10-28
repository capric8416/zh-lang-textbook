#!/usr/bin/env python3
"""Record, encode, decode and play speech with the SNAC 24 kHz model.

This is an isolated experiment. It does not integrate with the Flutter app.
The compact .snaclab container is local to this experiment; SNAC itself does
not publish a standard file container.
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
import tempfile
import time
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


MODEL_ID = "hubertsiuzdak/snac_24khz"
SAMPLE_RATE = 24_000
CODEBOOK_SIZE = 4_096
BITS_PER_TOKEN = 12
MAGIC = b"SNACLB01"
VERSION = 1
HEADER = struct.Struct("<8sHHIIQ")
UINT32 = struct.Struct("<I")


@dataclass(frozen=True)
class PackedSnac:
    sample_rate: int
    sample_count: int
    codebook_size: int
    codes: tuple[tuple[int, ...], ...]

    @property
    def duration_seconds(self) -> float:
        return self.sample_count / self.sample_rate


def pack_values(values: Sequence[int], bits: int) -> bytes:
    """Pack unsigned integers into a contiguous little-endian bit stream."""
    if bits <= 0 or bits > 24:
        raise ValueError(f"unsupported bit width: {bits}")
    limit = 1 << bits
    output = bytearray()
    accumulator = 0
    available = 0
    for value in values:
        value = int(value)
        if not 0 <= value < limit:
            raise ValueError(f"token {value} does not fit in {bits} bits")
        accumulator |= value << available
        available += bits
        while available >= 8:
            output.append(accumulator & 0xFF)
            accumulator >>= 8
            available -= 8
    if available:
        output.append(accumulator & 0xFF)
    return bytes(output)


def unpack_values(payload: bytes, count: int, bits: int) -> tuple[int, ...]:
    """Reverse :func:`pack_values` and reject truncated payloads."""
    values: list[int] = []
    mask = (1 << bits) - 1
    accumulator = 0
    available = 0
    offset = 0
    while len(values) < count:
        while available < bits:
            if offset >= len(payload):
                raise ValueError("truncated token payload")
            accumulator |= payload[offset] << available
            available += 8
            offset += 1
        values.append(accumulator & mask)
        accumulator >>= bits
        available -= bits
    if offset != len(payload):
        raise ValueError("token payload has trailing bytes")
    return tuple(values)


def write_container(path: Path, item: PackedSnac) -> None:
    if item.sample_rate <= 0 or item.sample_count <= 0:
        raise ValueError("sample rate and sample count must be positive")
    if item.codebook_size < 2:
        raise ValueError("codebook size must be at least 2")
    bits = math.ceil(math.log2(item.codebook_size))
    header = HEADER.pack(
        MAGIC,
        VERSION,
        len(item.codes),
        item.sample_rate,
        item.codebook_size,
        item.sample_count,
    )
    body = bytearray(header)
    for level in item.codes:
        payload = pack_values(level, bits)
        body.extend(UINT32.pack(len(level)))
        body.extend(UINT32.pack(len(payload)))
        body.extend(payload)
    body.extend(UINT32.pack(zlib.crc32(body)))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)


def read_container(path: Path) -> PackedSnac:
    data = path.read_bytes()
    if len(data) < HEADER.size + UINT32.size:
        raise ValueError("file is too short to be a .snaclab container")
    expected_crc = UINT32.unpack_from(data, len(data) - UINT32.size)[0]
    actual_crc = zlib.crc32(data[:-UINT32.size])
    if actual_crc != expected_crc:
        raise ValueError("container checksum does not match")
    magic, version, levels, sample_rate, codebook_size, sample_count = (
        HEADER.unpack_from(data)
    )
    if magic != MAGIC:
        raise ValueError("not a SNAC audio lab container")
    if version != VERSION:
        raise ValueError(f"unsupported container version: {version}")
    if levels == 0 or levels > 32:
        raise ValueError(f"invalid level count: {levels}")
    bits = math.ceil(math.log2(codebook_size))
    offset = HEADER.size
    end = len(data) - UINT32.size
    codes: list[tuple[int, ...]] = []
    for _ in range(levels):
        if offset + UINT32.size * 2 > end:
            raise ValueError("truncated level header")
        count = UINT32.unpack_from(data, offset)[0]
        payload_size = UINT32.unpack_from(data, offset + UINT32.size)[0]
        offset += UINT32.size * 2
        payload_end = offset + payload_size
        if payload_end > end:
            raise ValueError("truncated level payload")
        codes.append(unpack_values(data[offset:payload_end], count, bits))
        offset = payload_end
    if offset != end:
        raise ValueError("container has trailing data")
    return PackedSnac(sample_rate, sample_count, codebook_size, tuple(codes))


def _audio_modules():
    try:
        import numpy as np
        import soundfile as sf
    except ImportError as error:
        raise SystemExit(
            "缺少音频依赖，请按 snac_audio_lab.md 安装实验环境。"
        ) from error
    return np, sf


def _model_modules():
    try:
        import torch
        from snac import SNAC
    except ImportError as error:
        raise SystemExit(
            "缺少 SNAC/PyTorch，请按 snac_audio_lab.md 安装实验环境。"
        ) from error
    return torch, SNAC


def choose_compute_device(requested: str, torch) -> str:
    if requested != "auto":
        return requested
    if torch.cuda.is_available():
        return "cuda"
    mps = getattr(torch.backends, "mps", None)
    if mps is not None and mps.is_available():
        return "mps"
    return "cpu"


def load_model(requested_device: str):
    torch, SNAC = _model_modules()
    device = choose_compute_device(requested_device, torch)
    started = time.monotonic()
    model = SNAC.from_pretrained(MODEL_ID).eval().to(device)
    print(f"模型已加载到 {device}，耗时 {time.monotonic() - started:.2f} 秒")
    return torch, model, device


def load_mono_24khz(path: Path):
    np, sf = _audio_modules()
    audio, source_rate = sf.read(path, dtype="float32", always_2d=True)
    audio = audio.mean(axis=1)
    if source_rate != SAMPLE_RATE:
        try:
            import soxr
        except ImportError as error:
            raise SystemExit("输入不是 24 kHz，重采样需要安装 soxr。") from error
        audio = soxr.resample(audio, source_rate, SAMPLE_RATE, quality="HQ")
    audio = np.ascontiguousarray(np.clip(audio, -1.0, 1.0), dtype=np.float32)
    if audio.size == 0:
        raise ValueError("input audio is empty")
    return audio


def save_wav(path: Path, audio) -> None:
    _, sf = _audio_modules()
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(path, audio, SAMPLE_RATE, subtype="PCM_16")


def record_wav(path: Path, seconds: float, input_device: str | None) -> None:
    if seconds <= 0:
        raise ValueError("recording duration must be positive")
    np, _ = _audio_modules()
    try:
        import sounddevice as sd
    except ImportError as error:
        raise SystemExit("录音需要安装 sounddevice。") from error
    frame_count = round(seconds * SAMPLE_RATE)
    device: int | str | None = input_device
    if input_device is not None and input_device.isdigit():
        device = int(input_device)
    print(f"开始录音：{seconds:g} 秒，24 kHz 单声道……")
    audio = sd.rec(
        frame_count,
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype="float32",
        device=device,
    )
    sd.wait()
    save_wav(path, np.ravel(audio))
    print(f"原始录音已保存：{path} ({path.stat().st_size} bytes)")


def encode_wav(
    input_path: Path,
    output_path: Path,
    requested_device: str,
) -> PackedSnac:
    np, _ = _audio_modules()
    audio = load_mono_24khz(input_path)
    torch, model, device = load_model(requested_device)
    tensor = torch.from_numpy(np.array(audio, copy=True)).reshape(1, 1, -1).to(device)
    started = time.monotonic()
    with torch.inference_mode():
        encoded = model.encode(tensor)
    elapsed = time.monotonic() - started
    codes = tuple(
        tuple(int(value) for value in level.detach().cpu().reshape(-1).tolist())
        for level in encoded
    )
    item = PackedSnac(SAMPLE_RATE, len(audio), CODEBOOK_SIZE, codes)
    write_container(output_path, item)
    bitrate = output_path.stat().st_size * 8 / item.duration_seconds / 1000
    raw_size = len(audio) * 2
    print(
        f"SNAC 编码已保存：{output_path} ({output_path.stat().st_size} bytes, "
        f"{bitrate:.3f} kbps, PCM 压缩比 {raw_size / output_path.stat().st_size:.1f}:1)"
    )
    print(
        f"各层 token 数：{[len(level) for level in codes]}；"
        f"编码耗时 {elapsed:.2f} 秒"
    )
    return item


def decode_snac(
    input_path: Path,
    output_path: Path,
    requested_device: str,
):
    np, _ = _audio_modules()
    item = read_container(input_path)
    if item.sample_rate != SAMPLE_RATE or item.codebook_size != CODEBOOK_SIZE:
        raise ValueError("container does not match the snac_24khz model")
    torch, model, device = load_model(requested_device)
    codes = [
        torch.tensor(level, dtype=torch.int64, device=device).reshape(1, -1)
        for level in item.codes
    ]
    started = time.monotonic()
    with torch.inference_mode():
        decoded = model.decode(codes)
    elapsed = time.monotonic() - started
    audio = decoded.detach().cpu().reshape(-1).numpy()[: item.sample_count]
    audio = np.ascontiguousarray(np.clip(audio, -1.0, 1.0), dtype=np.float32)
    save_wav(output_path, audio)
    print(
        f"解码音频已保存：{output_path} ({len(audio) / SAMPLE_RATE:.2f} 秒)，"
        f"耗时 {elapsed:.2f} 秒"
    )
    return audio


def play_audio(audio) -> None:
    try:
        import sounddevice as sd
    except ImportError as error:
        raise SystemExit("播放需要安装 sounddevice。") from error
    sd.play(audio, SAMPLE_RATE)
    sd.wait()


def play_wav(path: Path) -> None:
    audio = load_mono_24khz(path)
    print(f"播放 {path}（{len(audio) / SAMPLE_RATE:.2f} 秒）")
    play_audio(audio)


def inspect_container(path: Path) -> None:
    item = read_container(path)
    size = path.stat().st_size
    print(f"文件：{path}")
    print(f"时长：{item.duration_seconds:.3f} 秒")
    print(f"采样率：{item.sample_rate} Hz")
    print(f"码本：{item.codebook_size}（{math.ceil(math.log2(item.codebook_size))} bit/token）")
    print(f"各层 token 数：{[len(level) for level in item.codes]}")
    print(f"文件大小：{size} bytes")
    print(f"实际码率（含容器）：{size * 8 / item.duration_seconds / 1000:.3f} kbps")


def self_test() -> None:
    levels = (
        tuple(range(12)),
        tuple((value * 37) % CODEBOOK_SIZE for value in range(24)),
        tuple((value * 101) % CODEBOOK_SIZE for value in range(48)),
    )
    item = PackedSnac(SAMPLE_RATE, SAMPLE_RATE, CODEBOOK_SIZE, levels)
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "roundtrip.snaclab"
        write_container(path, item)
        restored = read_container(path)
        if restored != item:
            raise AssertionError("container round trip changed data")
        damaged = bytearray(path.read_bytes())
        damaged[-5] ^= 1
        path.write_bytes(damaged)
        try:
            read_container(path)
        except ValueError as error:
            if "checksum" not in str(error):
                raise
        else:
            raise AssertionError("damaged container was accepted")
    print("容器 12-bit 打包、往返和校验测试通过。")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    record = subparsers.add_parser("record", help="录制并保存 24 kHz 单声道 WAV")
    record.add_argument("output", type=Path)
    record.add_argument("--seconds", type=float, default=8.0)
    record.add_argument("--input-device", help="sounddevice 的设备编号或名称")

    encode = subparsers.add_parser("encode", help="将 WAV 编码为紧凑 SNAC token")
    encode.add_argument("input", type=Path)
    encode.add_argument("output", type=Path)
    encode.add_argument("--device", default="auto", choices=("auto", "cpu", "cuda", "mps"))

    decode = subparsers.add_parser("decode", help="解码 SNAC token 并保存 WAV")
    decode.add_argument("input", type=Path)
    decode.add_argument("output", type=Path)
    decode.add_argument("--device", default="auto", choices=("auto", "cpu", "cuda", "mps"))
    decode.add_argument("--play", action="store_true", help="保存后立即播放")

    play = subparsers.add_parser("play", help="加载、转换为单声道 24 kHz 并播放音频")
    play.add_argument("input", type=Path)

    inspect = subparsers.add_parser("inspect", help="查看 .snaclab 容器信息")
    inspect.add_argument("input", type=Path)

    demo = subparsers.add_parser("demo", help="录音、编码、解码并依次播放原始和还原音频")
    demo.add_argument("output_dir", type=Path)
    demo.add_argument("--seconds", type=float, default=8.0)
    demo.add_argument("--input-device")
    demo.add_argument("--device", default="auto", choices=("auto", "cpu", "cuda", "mps"))
    demo.add_argument("--no-play", action="store_true")

    subparsers.add_parser("self-test", help="不下载模型，测试紧凑容器往返")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "record":
            record_wav(args.output, args.seconds, args.input_device)
        elif args.command == "encode":
            encode_wav(args.input, args.output, args.device)
        elif args.command == "decode":
            audio = decode_snac(args.input, args.output, args.device)
            if args.play:
                play_audio(audio)
        elif args.command == "play":
            play_wav(args.input)
        elif args.command == "inspect":
            inspect_container(args.input)
        elif args.command == "demo":
            args.output_dir.mkdir(parents=True, exist_ok=True)
            original = args.output_dir / "original.wav"
            encoded = args.output_dir / "recording.snaclab"
            restored = args.output_dir / "restored.wav"
            record_wav(original, args.seconds, args.input_device)
            encode_wav(original, encoded, args.device)
            decoded = decode_snac(encoded, restored, args.device)
            inspect_container(encoded)
            if not args.no_play:
                print("播放原始录音……")
                play_wav(original)
                print("播放 SNAC 还原录音……")
                play_audio(decoded)
        elif args.command == "self-test":
            self_test()
    except (OSError, RuntimeError, ValueError) as error:
        print(f"错误：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
