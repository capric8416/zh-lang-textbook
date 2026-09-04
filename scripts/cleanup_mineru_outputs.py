#!/usr/bin/env python3
"""Flatten MinerU output directories and retain only selected artifacts."""

from __future__ import annotations

import argparse
import shutil
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


CONTENT_LIST_V2_SUFFIX = "_content_list_v2.json"


@dataclass(frozen=True)
class Document:
    stem: str
    source_dir: Path
    source_container: Path
    target_dir: Path
    markdown: Path
    content_list_v2: Path
    images: Path


def parse_args() -> argparse.Namespace:
    repository_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description=(
            "遍历 MinerU 输出，只保留 Markdown、content_list_v2.json 和 images，"
            "并整理为 markdown/<文档名>/。默认仅预览。"
        )
    )
    parser.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=repository_root / "markdown",
        help="MinerU 输出根目录（默认：仓库中的 markdown/）",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="实际移动并删除文件；不指定时只显示操作计划",
    )
    return parser.parse_args()


def discover_documents(root: Path) -> list[Document]:
    documents: list[Document] = []
    seen_stems: dict[str, Path] = {}

    for content_list_v2 in sorted(root.rglob(f"*{CONTENT_LIST_V2_SUFFIX}")):
        if any(part.startswith(".mineru-cleanup-") for part in content_list_v2.parts):
            continue

        stem = content_list_v2.name.removesuffix(CONTENT_LIST_V2_SUFFIX)
        source_dir = content_list_v2.parent
        markdown = source_dir / f"{stem}.md"
        images = source_dir / "images"

        missing = [
            str(path)
            for path in (markdown, content_list_v2, images)
            if not path.exists()
        ]
        if missing:
            raise ValueError(
                f"{source_dir} 缺少必须保留的文件或目录：{', '.join(missing)}"
            )
        if not markdown.is_file() or not content_list_v2.is_file() or not images.is_dir():
            raise ValueError(f"{source_dir} 中保留项的类型不正确")

        previous = seen_stems.get(stem)
        if previous is not None:
            raise ValueError(f"发现重名文档 {stem!r}：{previous} 和 {source_dir}")
        seen_stems[stem] = source_dir

        relative = source_dir.relative_to(root)
        source_container = root / relative.parts[0]
        target_dir = root / stem
        documents.append(
            Document(
                stem=stem,
                source_dir=source_dir,
                source_container=source_container,
                target_dir=target_dir,
                markdown=markdown,
                content_list_v2=content_list_v2,
                images=images,
            )
        )

    validate_plan(documents)
    return documents


def validate_plan(documents: list[Document]) -> None:
    containers: dict[Path, str] = {}
    for document in documents:
        previous = containers.get(document.source_container)
        if previous is not None and previous != document.stem:
            raise ValueError(
                f"顶层目录 {document.source_container} 同时包含多份文档，拒绝自动清理"
            )
        containers[document.source_container] = document.stem

        already_flat = document.source_dir == document.target_dir
        if document.target_dir.exists() and not already_flat:
            raise ValueError(f"目标目录已存在：{document.target_dir}")


def print_plan(root: Path, documents: list[Document], apply: bool) -> None:
    mode = "执行" if apply else "预览"
    print(f"[{mode}] 根目录：{root}")
    for document in documents:
        print(f"- {document.source_dir} -> {document.target_dir}")
        print(f"  保留：{document.markdown.name}")
        print(f"  保留：{document.content_list_v2.name}")
        print("  保留：images/")
    print(f"共发现 {len(documents)} 份文档。")


def clean_already_flat(document: Document) -> None:
    keep = {
        document.markdown.name,
        document.content_list_v2.name,
        document.images.name,
    }
    for entry in document.target_dir.iterdir():
        if entry.name in keep:
            continue
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()


def apply_plan(root: Path, documents: list[Document]) -> None:
    nested = [document for document in documents if document.source_dir != document.target_dir]
    already_flat = [document for document in documents if document.source_dir == document.target_dir]

    staging_root = Path(tempfile.mkdtemp(prefix=".mineru-cleanup-", dir=root))
    try:
        for document in nested:
            staging_dir = staging_root / document.stem
            staging_dir.mkdir()
            shutil.move(str(document.markdown), staging_dir / document.markdown.name)
            shutil.move(
                str(document.content_list_v2),
                staging_dir / document.content_list_v2.name,
            )
            shutil.move(str(document.images), staging_dir / "images")

        for container in sorted(
            {document.source_container for document in nested},
            key=lambda path: len(path.parts),
            reverse=True,
        ):
            shutil.rmtree(container)

        for document in nested:
            shutil.move(str(staging_root / document.stem), document.target_dir)

        for document in already_flat:
            clean_already_flat(document)
    except Exception:
        print(
            f"清理失败；已搬出的保留文件仍在暂存目录：{staging_root}",
            file=sys.stderr,
        )
        raise
    else:
        shutil.rmtree(staging_root)


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        print(f"错误：目录不存在：{root}", file=sys.stderr)
        return 2

    try:
        documents = discover_documents(root)
    except (OSError, ValueError) as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 2

    if not documents:
        print(f"错误：{root} 下没有找到 *{CONTENT_LIST_V2_SUFFIX}", file=sys.stderr)
        return 2

    print_plan(root, documents, args.apply)
    if not args.apply:
        print("未修改任何文件；确认计划后添加 --apply 执行。")
        return 0

    apply_plan(root, documents)
    print("清理完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
