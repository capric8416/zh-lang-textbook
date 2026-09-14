import argparse

from .adapters import for_target


def main() -> None:
    parser = argparse.ArgumentParser(description="Build native OCR and speech dependencies")
    parser.add_argument("component", choices=("checkout", "patches", "ort", "re2", "piper", "funasr", "ocrdeps", "archive", "validate", "clean", "ocr", "speech", "all"))
    parser.add_argument("--target", required=True,
                        choices=("linux-x64", "android-arm64-v8a", "macos-arm64",
                                 "macos-x86_64", "ios-arm64", "windows-x64"))
    parser.add_argument("--module", choices=("all", "speech", "ocr", "flutter"), default="all",
                        help="modules to clean when component is clean (default: all)")
    parser.add_argument("--purge-sources", action="store_true",
                        help="also remove checked-out native dependency sources")
    parser.add_argument("--dry-run", action="store_true", help="list paths without removing them")
    args = parser.parse_args()
    if args.component == "clean":
        from .stages.clean import clean
        config = for_target(args.target).config
        modules = None if args.module == "all" else {args.module}
        clean(config, modules=modules, purge_sources=args.purge_sources, dry_run=args.dry_run)
    elif args.component == "checkout":
        from .stages.checkout import checkout_sources
        checkout_sources(for_target(args.target).config.root)
    elif args.component == "patches":
        from .stages.patches import patch_all
        patch_all(for_target(args.target).config)
    elif args.component == "ort":
        from .stages.checkout import checkout_sources
        from .stages.patches import patch_onnxruntime
        from .stages.onnxruntime import build
        config = for_target(args.target).config
        checkout_sources(config.root)
        patch_onnxruntime(config.speech / ".build-deps/sources/onnxruntime-v1.22.0")
        build(config)
        from .stages.re2 import build as build_re2
        build_re2(config)
    elif args.component == "re2":
        from .stages.checkout import checkout_sources
        from .stages.patches import patch_onnxruntime
        from .stages.onnxruntime import build as build_ort
        from .stages.re2 import build
        config = for_target(args.target).config
        checkout_sources(config.root)
        patch_onnxruntime(config.speech / ".build-deps/sources/onnxruntime-v1.22.0")
        build_ort(config)
        build(config)
    elif args.component == "piper":
        from .stages.checkout import checkout_sources
        from .stages.patches import patch_onnxruntime
        from .stages.onnxruntime import build as build_ort
        from .stages.piper import build
        config = for_target(args.target).config
        checkout_sources(config.root)
        patch_onnxruntime(config.speech / ".build-deps/sources/onnxruntime-v1.22.0")
        build_ort(config)
        from .stages.re2 import build as build_re2
        build_re2(config)
        build(config)
    elif args.component == "funasr":
        from .stages.checkout import checkout_sources
        from .stages.patches import patch_onnxruntime
        from .stages.onnxruntime import build as build_ort
        from .stages.funasr import build
        config = for_target(args.target).config
        checkout_sources(config.root)
        patch_onnxruntime(config.speech / ".build-deps/sources/onnxruntime-v1.22.0")
        build_ort(config)
        from .stages.re2 import build as build_re2
        build_re2(config)
        build(config)
    elif args.component == "ocrdeps":
        from .stages.checkout import checkout_sources
        from .stages.ocr import build
        config = for_target(args.target).config
        checkout_sources(config.root)
        build(config)
    elif args.component == "archive":
        from .stages.archive import build
        build(for_target(args.target).config)
    elif args.component == "validate":
        from .stages.validate import validate
        validate(for_target(args.target).config)
    elif args.component in ("speech", "ocr", "all"):
        from .pipeline import all_components, ocr, speech
        config = for_target(args.target).config
        {"speech": speech, "ocr": ocr, "all": all_components}[args.component](config)
    else:
        for_target(args.target).build(args.component)


if __name__ == "__main__":
    main()
