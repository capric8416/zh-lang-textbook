#!/usr/bin/env python3
"""Convert an MP4 animation to a transparent looping WebP.

Requirements:
  * ffmpeg and ffprobe
  * ImageMagick 7 (the ``magick`` command)
  * rembg with CPU + CLI support, or uvx (the default runner)

The first run through uvx may download rembg dependencies and its model.

Example:
  python3 scripts/video_to_transparent_webp.py input.mp4 output.webp
  python3 scripts/video_to_transparent_webp.py input.mp4 output.webp --fps 15 --size 512
  python3 scripts/video_to_transparent_webp.py images/a/v4/happy.mp4 /tmp/happy.webp
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def run(command: list[str], *, capture: bool = False) -> str:
    result = subprocess.run(
        command,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def require_program(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f"Required program not found on PATH: {name}")
    return path


def video_dimensions(ffprobe: str, source: Path) -> tuple[int, int]:
    raw = run(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "json",
            str(source),
        ],
        capture=True,
    )
    streams = json.loads(raw).get("streams", [])
    if not streams:
        raise RuntimeError(f"No video stream found in {source}")
    return int(streams[0]["width"]), int(streams[0]["height"])


def background_removal_command(model: str, source_dir: Path, output_dir: Path) -> list[str]:
    rembg = shutil.which("rembg")
    if rembg:
        return [rembg, "p", "-m", model, str(source_dir), str(output_dir)]

    uvx = shutil.which("uvx")
    if uvx:
        return [
            uvx,
            "--from",
            "rembg[cpu,cli]",
            "rembg",
            "p",
            "-m",
            model,
            str(source_dir),
            str(output_dir),
        ]
    raise RuntimeError("Install rembg[cpu,cli] or install uv/uvx to run it on demand")


def alpha_bounds(magick: str, frame: Path) -> tuple[int, int, int, int] | None:
    geometry = run(
        [
            magick,
            str(frame),
            "-channel",
            "A",
            "-threshold",
            "8%",
            "-trim",
            "-format",
            "%w %h %X %Y",
            "info:",
        ],
        capture=True,
    )
    if not geometry:
        return None
    width, height, left, top = (int(value) for value in geometry.split())
    return left, top, left + width, top + height


def process_frames(
    magick: str,
    frames: list[Path],
    output_dir: Path,
    input_width: int,
    input_height: int,
    size: int,
    margin: float,
) -> None:
    bounds = [box for frame in frames if (box := alpha_bounds(magick, frame))]
    if not bounds:
        raise RuntimeError("Background removal produced no visible subject pixels")

    left = min(box[0] for box in bounds)
    top = min(box[1] for box in bounds)
    right = max(box[2] for box in bounds)
    bottom = max(box[3] for box in bounds)
    subject_width = right - left
    subject_height = bottom - top
    side = math.ceil(max(subject_width, subject_height) * (1 + 2 * margin))
    center_x = (left + right) / 2
    center_y = (top + bottom) / 2
    crop_left = round(center_x - side / 2)
    crop_top = round(center_y - side / 2)

    # Pad every frame by ``side`` first, so even a crop extending beyond the
    # original video edges stays transparent and has identical dimensions.
    padded_width = input_width + 2 * side
    padded_height = input_height + 2 * side
    crop_x = side + crop_left
    crop_y = side + crop_top
    output_dir.mkdir(parents=True, exist_ok=True)

    for frame in frames:
        destination = output_dir / frame.name
        run(
            [
                magick,
                str(frame),
                "-background",
                "none",
                "-gravity",
                "center",
                "-extent",
                f"{padded_width}x{padded_height}",
                "-gravity",
                "northwest",
                "-crop",
                f"{side}x{side}+{crop_x}+{crop_y}",
                "+repage",
                "-filter",
                "Lanczos",
                "-resize",
                f"{size}x{size}",
                str(destination),
            ]
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_mp4", type=Path, help="source MP4 video")
    parser.add_argument("output_webp", type=Path, help="destination animated WebP")
    parser.add_argument("--fps", type=float, default=15, help="output frame rate (default: 15)")
    parser.add_argument("--size", type=int, default=512, help="square output canvas (default: 512)")
    parser.add_argument("--max-dimension", type=int, default=640, help="max source frame edge for processing (default: 640)")
    parser.add_argument("--margin", type=float, default=0.10, help="transparent framing margin on each side (default: 0.10)")
    parser.add_argument("--model", default="u2netp", help="rembg model (default: u2netp)")
    parser.add_argument("--quality", type=int, default=82, help="WebP quality, 0-100 (default: 82)")
    parser.add_argument("--force", action="store_true", help="overwrite the output file if it already exists")
    args = parser.parse_args()

    source = args.input_mp4.expanduser().resolve()
    destination = args.output_webp.expanduser().resolve()
    if not source.is_file():
        parser.error(f"Input video does not exist: {source}")
    if source == destination:
        parser.error("Input and output paths must be different")
    if destination.exists() and not args.force:
        parser.error(f"Output already exists (pass --force to replace it): {destination}")
    if args.fps <= 0 or args.size <= 0 or args.max_dimension <= 0:
        parser.error("fps, size, and max-dimension must be positive")
    if args.margin < 0 or args.margin > 1:
        parser.error("margin must be between 0 and 1")
    if not 0 <= args.quality <= 100:
        parser.error("quality must be between 0 and 100")

    try:
        ffmpeg = require_program("ffmpeg")
        ffprobe = require_program("ffprobe")
        magick = require_program("magick")
        video_width, video_height = video_dimensions(ffprobe, source)
        scale = min(args.max_dimension / video_width, args.max_dimension / video_height, 1)
        scaled_width = max(2, round(video_width * scale / 2) * 2)
        scaled_height = max(2, round(video_height * scale / 2) * 2)

        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(
            prefix=".video-to-webp-",
            dir=destination.parent,
        ) as temporary:
            work = Path(temporary)
            extracted = work / "extracted"
            transparent = work / "transparent"
            canvas = work / "canvas"
            encoded = work / "animation.webp"
            extracted.mkdir()
            transparent.mkdir()

            run(
                [
                    ffmpeg,
                    "-y",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-i",
                    str(source),
                    "-vf",
                    f"fps={args.fps:g},scale={scaled_width}:{scaled_height}:flags=lanczos",
                    "-start_number",
                    "1",
                    str(extracted / "frame-%04d.png"),
                ]
            )
            extracted_frames = sorted(extracted.glob("frame-*.png"))
            if not extracted_frames:
                raise RuntimeError("ffmpeg did not extract any frames")

            run(background_removal_command(args.model, extracted, transparent))
            transparent_frames = sorted(transparent.glob("frame-*.png"))
            if len(transparent_frames) != len(extracted_frames):
                raise RuntimeError(
                    f"rembg returned {len(transparent_frames)} frames; expected {len(extracted_frames)}"
                )

            process_frames(
                magick,
                transparent_frames,
                canvas,
                scaled_width,
                scaled_height,
                args.size,
                args.margin,
            )
            run(
                [
                    magick,
                    "-limit",
                    "list-length",
                    "512",
                    "-delay",
                    str(max(1, round(100 / args.fps))),
                    "-dispose",
                    "background",
                    "-loop",
                    "0",
                    "-define",
                    "webp:lossless=false",
                    "-define",
                    "webp:method=0",
                    "-define",
                    "webp:alpha-quality=100",
                    "-quality",
                    str(args.quality),
                    *[str(frame) for frame in sorted(canvas.glob("frame-*.png"))],
                    str(encoded),
                ]
            )
            encoded.replace(destination)
        print(f"Created {destination} ({len(extracted_frames)} frames at {args.fps:g} FPS)")
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
