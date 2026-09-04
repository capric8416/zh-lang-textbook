#!/usr/bin/env -S uv run python
"""Repair MinerU's extraction of the textbooks' encoded pinyin font."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

import fitz


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = REPOSITORY_ROOT / "src"
if str(SOURCE_ROOT) not in sys.path:
    sys.path.insert(0, str(SOURCE_ROOT))

from zh_textbook_parser.pinyin_font import TONE_CIPHER, decode, is_ruby_font


TOKEN_RE = re.compile(r"[A-Za-züÜv]+")
UPPER_TONE_CIPHER = set(TONE_CIPHER) - {"v"}


@dataclass(frozen=True)
class Document:
    stem: str
    pdf: Path
    markdown: Path
    content_list_v2: Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "根据同名 PDF 的 HanyuXi 拼音字体修复 MinerU 输出中的声调乱码。"
            "默认仅预览。"
        )
    )
    parser.add_argument(
        "--markdown-root",
        type=Path,
        default=REPOSITORY_ROOT / "markdown",
        help="MinerU 输出根目录（默认：仓库中的 markdown/）",
    )
    parser.add_argument(
        "--pdf-root",
        type=Path,
        default=REPOSITORY_ROOT / "pdf",
        help="原始 PDF 根目录（默认：仓库中的 pdf/）",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="实际写入修复；不指定时只显示预览报告",
    )
    return parser.parse_args()


def discover_documents(markdown_root: Path, pdf_root: Path) -> list[Document]:
    documents: list[Document] = []
    for directory in sorted(path for path in markdown_root.iterdir() if path.is_dir()):
        stem = directory.name
        markdown = directory / f"{stem}.md"
        content_list_v2 = directory / f"{stem}_content_list_v2.json"
        if not markdown.exists() and not content_list_v2.exists():
            continue

        missing = [
            str(path)
            for path in (markdown, content_list_v2, pdf_root / f"{stem}.pdf")
            if not path.is_file()
        ]
        if missing:
            raise ValueError(f"{stem} 缺少输入文件：{', '.join(missing)}")

        documents.append(
            Document(
                stem=stem,
                pdf=pdf_root / f"{stem}.pdf",
                markdown=markdown,
                content_list_v2=content_list_v2,
            )
        )
    return documents


def pinyin_mapping_from_pdf(pdf_path: Path) -> dict[str, str]:
    """Return encoded-token -> Unicode-pinyin mappings found in ruby-font spans."""
    mapping: dict[str, str] = {}
    with fitz.open(pdf_path) as document:
        for page in document:
            for block in page.get_text("dict")["blocks"]:
                if block["type"] == 1:
                    continue
                for line in block.get("lines", []):
                    for span in line.get("spans", []):
                        if not is_ruby_font(span.get("font", "")):
                            continue
                        for raw in TOKEN_RE.findall(span.get("text", "")):
                            mapping[raw] = decode(raw)
    return mapping


def decode_compound_token(token: str, mapping: dict[str, str]) -> str | None:
    """Decode a MinerU token made by joining multiple known PDF pinyin tokens."""
    if not any(character in UPPER_TONE_CIPHER for character in token):
        return None

    best: list[list[str] | None] = [None] * (len(token) + 1)
    best[0] = []
    for start in range(len(token)):
        if best[start] is None:
            continue
        for end in range(start + 1, len(token) + 1):
            part = token[start:end]
            if part not in mapping:
                continue
            candidate = [*best[start], part]
            if best[end] is None or len(candidate) < len(best[end]):
                best[end] = candidate

    parts = best[-1]
    if parts is None or len(parts) < 2 or max(map(len, parts)) < 2:
        return None
    corrected = "".join(mapping[part] for part in parts)
    return corrected if corrected != token else None


def replace_encoded_tokens(
    text: str, mapping: dict[str, str]
) -> tuple[str, Counter[str]]:
    replacements: Counter[str] = Counter()
    compound_cache: dict[str, str | None] = {}

    def replace(match: re.Match[str]) -> str:
        raw = match.group(0)
        corrected = mapping.get(raw)
        if corrected == raw:
            return raw
        if corrected is None:
            corrected = compound_cache.setdefault(
                raw, decode_compound_token(raw, mapping)
            )
        if corrected is None:
            return raw
        replacements[raw] += 1
        return corrected

    return TOKEN_RE.sub(replace, text), replacements


def suspicious_unmapped_tokens(text: str, mapping: dict[str, str]) -> set[str]:
    """Find still-encoded-looking tokens for the report; never auto-replace them."""
    return {
        token
        for token in TOKEN_RE.findall(text)
        if token not in mapping
        and any(character in UPPER_TONE_CIPHER for character in token)
        and any(character.islower() for character in token)
    }


def transform_json_value(
    value: object, mapping: dict[str, str]
) -> tuple[object, Counter[str], set[str]]:
    replacements: Counter[str] = Counter()
    unmapped: set[str] = set()

    if isinstance(value, str):
        corrected, string_replacements = replace_encoded_tokens(value, mapping)
        replacements.update(string_replacements)
        unmapped.update(suspicious_unmapped_tokens(corrected, mapping))
        return corrected, replacements, unmapped

    if isinstance(value, list):
        corrected_items: list[object] = []
        for item in value:
            corrected, item_replacements, item_unmapped = transform_json_value(
                item, mapping
            )
            corrected_items.append(corrected)
            replacements.update(item_replacements)
            unmapped.update(item_unmapped)
        return corrected_items, replacements, unmapped

    if isinstance(value, dict):
        corrected_dict: dict[object, object] = {}
        for key, item in value.items():
            corrected, item_replacements, item_unmapped = transform_json_value(
                item, mapping
            )
            corrected_dict[key] = corrected
            replacements.update(item_replacements)
            unmapped.update(item_unmapped)
        return corrected_dict, replacements, unmapped

    return value, replacements, unmapped


def atomic_write(path: Path, text: str) -> None:
    mode = path.stat().st_mode
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="",
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=path.parent,
            delete=False,
        ) as temporary:
            temporary.write(text)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_name = temporary.name
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, path)
    except Exception:
        if temporary_name is not None:
            Path(temporary_name).unlink(missing_ok=True)
        raise


def process_document(document: Document, apply: bool) -> tuple[int, set[str]]:
    mapping = pinyin_mapping_from_pdf(document.pdf)
    if not mapping:
        raise ValueError(f"{document.pdf} 中没有找到 HanyuXi 拼音字体")

    pending_writes: list[tuple[Path, str]] = []
    total_replacements: Counter[str] = Counter()
    unmapped: set[str] = set()

    for path in (document.markdown, document.content_list_v2):
        original = path.read_text(encoding="utf-8")
        if path.suffix == ".json":
            parsed = json.loads(original)
            corrected_value, replacements, file_unmapped = transform_json_value(
                parsed, mapping
            )
            corrected = json.dumps(corrected_value, ensure_ascii=False, indent=4)
            if original.endswith("\n"):
                corrected += "\n"
        else:
            corrected, replacements = replace_encoded_tokens(original, mapping)
            file_unmapped = suspicious_unmapped_tokens(corrected, mapping)

        total_replacements.update(replacements)
        unmapped.update(file_unmapped)

        if path.suffix == ".json":
            json.loads(corrected)
        if corrected != original:
            pending_writes.append((path, corrected))

    if apply:
        for path, corrected in pending_writes:
            atomic_write(path, corrected)

    print(
        f"- {document.stem}: PDF 映射 {len(mapping)} 个 token，"
        f"替换 {sum(total_replacements.values())} 处 / "
        f"{len(total_replacements)} 种"
    )
    if unmapped:
        preview = ", ".join(sorted(unmapped)[:12])
        remainder = len(unmapped) - 12
        suffix = f"，另有 {remainder} 种" if remainder > 0 else ""
        print(f"  未自动处理的可疑 token：{preview}{suffix}")

    return sum(total_replacements.values()), unmapped


def main() -> int:
    args = parse_args()
    markdown_root = args.markdown_root.resolve()
    pdf_root = args.pdf_root.resolve()
    if not markdown_root.is_dir() or not pdf_root.is_dir():
        print(
            f"错误：输入目录不存在：markdown={markdown_root}, pdf={pdf_root}",
            file=sys.stderr,
        )
        return 2

    try:
        documents = discover_documents(markdown_root, pdf_root)
        if not documents:
            raise ValueError(f"{markdown_root} 下没有找到 MinerU Markdown/JSON")

        mode = "执行" if args.apply else "预览"
        print(f"[{mode}] 共发现 {len(documents)} 份文档")
        replacement_count = 0
        documents_with_unmapped = 0
        for document in documents:
            count, unmapped = process_document(document, args.apply)
            replacement_count += count
            documents_with_unmapped += bool(unmapped)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 2

    print(f"合计可修复 {replacement_count} 处。")
    if documents_with_unmapped:
        print(
            f"警告：{documents_with_unmapped} 份文档仍有未确认的可疑 token；"
            "这些内容未被自动修改。"
        )
    if not args.apply:
        print("未修改任何文件；确认报告后添加 --apply 执行。")
    else:
        print("修复完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
