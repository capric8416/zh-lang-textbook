"""Apply reproducible source patches before a dependency is configured."""

import shutil
import subprocess
import re
from pathlib import Path

from ..runner import run


def replace(path: Path, old: str, new: str, *, required: bool = True) -> None:
    text = path.read_text()
    if old not in text:
        if required:
            raise RuntimeError(f"patch context not found: {path}: {old!r}")
        return
    path.write_text(text.replace(old, new, 1))


def patch_onnxruntime(source: Path) -> None:
    replace(source / "cmake" / "deps.txt",
            "5ea4d05e62d7f954a46b3213f9b2535bdd866803",
            "51982be81bbe52572b54180454df11a3ece9a934", required=False)
    replace(source / "onnxruntime/core/optimizer/transpose_optimization/optimizer_api.h",
            "#include <functional>", "#include <cstdint>\n#include <functional>", required=False)
    replace(source / "cmake/onnxruntime_mlas.cmake",
            'if(NOT "${CMAKE_CXX_COMPILER_ID}" STREQUAL "GNU" OR CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "11")',
            'if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "11")',
            required=False)


def patch_piper(source: Path, work: Path) -> None:
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(source / "libpiper", work)
    shutil.copy2(source / "setup.py", work.parent / "setup.py")
    replace(work / "CMakeLists.txt", "cmake_minimum_required(VERSION 3.26)",
            "cmake_minimum_required(VERSION 3.16)", required=False)
    replace(work / "CMakeLists.txt", "add_library(piper SHARED", "add_library(piper STATIC", required=False)
    # The default ExternalProject clone is shallow and can omit espeak-ng's
    # phoneme source data. Force a complete checkout so phondata compilation
    # sees every phsource file.
    replace(work / "CMakeLists.txt", "    PREFIX ${ESPEAKNG_BUILD_DIR}",
            "    PREFIX ${ESPEAKNG_BUILD_DIR}\n    GIT_SHALLOW FALSE",
            required=False)
    replace(work / "CMakeLists.txt", "GIT_TAG 212928b394a96e8fd2096616bfd54e17845c48f6",
            "GIT_TAG master", required=False)
    replace(work / "CMakeLists.txt", "ExternalProject_Add(espeak_ng_external",
            "set(ESPEAKNG_TOOLCHAIN_ARGS)\n"
            "if(ANDROID)\n"
            "  list(APPEND ESPEAKNG_TOOLCHAIN_ARGS\n"
            "    \"-DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE}\"\n"
            "    \"-DANDROID_ABI=${ANDROID_ABI}\"\n"
            "    \"-DANDROID_PLATFORM=${ANDROID_PLATFORM}\")\n"
            "elseif(APPLE AND CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
            "  list(APPEND ESPEAKNG_TOOLCHAIN_ARGS\n"
            "    \"-DCMAKE_SYSTEM_NAME=iOS\"\n"
            "    \"-DCMAKE_OSX_SYSROOT=${CMAKE_OSX_SYSROOT}\"\n"
            "    \"-DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}\"\n"
            "    \"-DCMAKE_OSX_DEPLOYMENT_TARGET=${CMAKE_OSX_DEPLOYMENT_TARGET}\")\n"
            "endif()\n\n"
            "ExternalProject_Add(espeak_ng_external", required=False)
    replace(work / "CMakeLists.txt",
            '        "-DCMAKE_CXX_FLAGS=-D_FILE_OFFSET_BITS=64 -I${ESPEAKNG_BUILD_DIR}/src/espeak_ng_external/src/ucd-tools/src/include"\n'
            "    BUILD_BYPRODUCTS",
            '        "-DCMAKE_CXX_FLAGS=-D_FILE_OFFSET_BITS=64 -I${ESPEAKNG_BUILD_DIR}/src/espeak_ng_external/src/ucd-tools/src/include"\n'
            "        ${ESPEAKNG_TOOLCHAIN_ARGS}\n"
            "    BUILD_BYPRODUCTS", required=False)
    patch_file = Path(__file__).resolve().parents[3] / "app/native/speech/patches/piper-pinyin-whitespace.patch"
    if patch_file.exists():
        run(["patch", "--batch", "--forward", "-p1", "-d", work, "-i", patch_file])


def patch_funasr(source: Path, work: Path) -> None:
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(source, work)
    replace(work / "src/CMakeLists.txt", "add_library(funasr SHARED", "add_library(funasr STATIC", required=False)
    runtime_header = work / "include/funasrruntime.h"
    if runtime_header.exists():
        header_text = runtime_header.read_text()
        if not header_text.startswith("#pragma once"):
            runtime_header.write_text("#pragma once\n" + header_text)
    # FunASR's runtime CMake expects this header, but the upstream runtime
    # snapshot does not include its json dependency.
    json_source = source.parents[2] / "nlohmann-json-3.11.3" / "single_include/nlohmann/json.hpp"
    json_target = work / "third_party/json/include/nlohmann/json.hpp"
    if json_source.exists():
        json_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(json_source, json_target)
    replace(work / "include/offline-stream.h",
            '#if !defined(__APPLE__)\n#include "itn-model.h"\n#include "com-define.h"\n#endif',
            '#if !defined(__APPLE__)\n#include "itn-model.h"\n#endif\n#include "com-define.h"', required=False)
    replace(work / "third_party/jieba/include/limonp/StringUtil.hpp",
            "std::not1(std::ptr_fun<unsigned, bool>(IsSpace))",
            "[](unsigned c) { return !IsSpace(c); }", required=False)
    replace(work / "third_party/jieba/include/limonp/StringUtil.hpp",
            "std::not1(std::bind2nd(std::equal_to<char>(), x))",
            "[x](char c) { return c != x; }", required=False)
    replace(work / "third_party/jieba/include/limonp/StringUtil.hpp",
            "std::find_if(s.rbegin(), s.rend(), std::not1(std::ptr_fun<unsigned, bool>(IsSpace)))",
            "std::find_if(s.rbegin(), s.rend(), [](unsigned c) { return !IsSpace(c); })", required=False)
    replace(work / "third_party/jieba/include/limonp/StringUtil.hpp",
            "std::find_if(s.rbegin(), s.rend(), std::not1(std::bind2nd(std::equal_to<char>(), x)))",
            "std::find_if(s.rbegin(), s.rend(), [x](char c) { return c != x; })", required=False)
    # OpenFST forcibly enables its host command-line binaries on every
    # non-Windows platform.  Under an iOS toolchain CMake treats those
    # executables as application bundles, while OpenFST's legacy install rule
    # has no BUNDLE DESTINATION.  FunASR only consumes libfst, so omit the
    # script/tool layer when cross-compiling for iOS.
    replace(work / "third_party/openfst/CMakeLists.txt",
            "if (WIN32)\n    set(HAVE_BIN OFF CACHE BOOL \"Build the fst binaries\" FORCE)",
            "if (WIN32 OR CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
            "    set(HAVE_BIN OFF CACHE BOOL \"Build the fst binaries\" FORCE)",
            required=False)
    replace(work / "src/tensor.h", "aligned_free(buff)", "AlignedFree(buff)", required=False)
    # Compatibility fixes for current libc++/libstdc++ and newer clang.
    replace(work / "third_party/openfst/src/include/fst/fst.h",
            "isymbols_ = impl.isymbols_ ? impl.isymbols_->Copy() : nullptr;",
            "isymbols_.reset(impl.isymbols_ ? impl.isymbols_->Copy() : nullptr);",
            required=False)
    replace(work / "third_party/openfst/src/include/fst/fst.h",
            "osymbols_ = impl.osymbols_ ? impl.osymbols_->Copy() : nullptr;",
            "osymbols_.reset(impl.osymbols_ ? impl.osymbols_->Copy() : nullptr);",
            required=False)
    replace(work / "third_party/openfst/src/include/fst/bi-table.h",
            "new S(table.s_)", "new S(*table.selector_)", required=False)
    replace(work / "third_party/kaldi-native-fbank/kaldi-native-fbank/csrc/rfft.h",
            "#include <memory>", "#include <cstdint>\n#include <memory>", required=False)
    replace(work / "src/util.h", "#define UTIL_H", "#define UTIL_H\n#include <cstdint>", required=False)
    # libc++ 19 no longer provides char_traits for unsigned byte/UTF-16
    # character types used by FunASR's legacy EncodeConverter aliases.
    replace(work / "src/encode_converter.h", "#include <vector>",
            "#include <vector>\nnamespace std {\n"
            "template <> struct char_traits<unsigned char> : char_traits<char> {\n"
            "  using char_type = unsigned char; using int_type = int;\n"
            "  using off_type = streamoff; using pos_type = streampos; using state_type = mbstate_t;\n"
            "  static void assign(char_type& r, const char_type& a) { r = a; }\n"
            "  static char_type* copy(char_type* d, const char_type* s, size_t n) { for(size_t i=0;i<n;++i)d[i]=s[i]; return d; }\n"
            "  static char_type* move(char_type* d, const char_type* s, size_t n) { return copy(d,s,n); }\n"
            "  static bool eq(char_type a, char_type b) { return a == b; }\n"
            "  static bool lt(char_type a, char_type b) { return a < b; }\n"
            "  static int compare(const char_type* a, const char_type* b, size_t n) { while (n-- && *a == *b) ++a, ++b; return n == size_t(-1) ? 0 : (*a < *b ? -1 : 1); }\n"
            "  static size_t length(const char_type* s) { size_t n=0; while (*s++) ++n; return n; }\n"
            "  static const char_type* find(const char_type* s, size_t n, const char_type& c) { while (n--) { if (*s == c) return s; ++s; } return nullptr; }\n"
            "  static int_type to_int_type(char_type c) { return c; } static char_type to_char_type(int_type c) { return static_cast<char_type>(c); }\n"
            "  static bool eq_int_type(int_type a, int_type b) { return a == b; } static int_type eof() { return -1; } static int_type not_eof(int_type c) { return c == eof() ? 0 : c; }\n"
            "};\n"
            "template <> struct char_traits<unsigned short> : char_traits<char> {\n"
            "  using char_type = unsigned short; using int_type = int; using off_type = streamoff; using pos_type = streampos; using state_type = mbstate_t;\n"
            "  static void assign(char_type& r, const char_type& a) { r = a; } static char_type* copy(char_type*d,const char_type*s,size_t n){for(size_t i=0;i<n;++i)d[i]=s[i];return d;} static char_type* move(char_type*d,const char_type*s,size_t n){return copy(d,s,n);} static bool eq(char_type a,char_type b){return a==b;} static bool lt(char_type a,char_type b){return a<b;}\n"
            "  static int compare(const char_type* a,const char_type* b,size_t n){while(n--&&*a==*b)++a,++b;return n==size_t(-1)?0:(*a<*b?-1:1);}\n"
            "  static size_t length(const char_type* s){size_t n=0;while(*s++)++n;return n;} static const char_type* find(const char_type*s,size_t n,const char_type&c){while(n--){if(*s==c)return s;++s;}return nullptr;}\n"
            "  static int_type to_int_type(char_type c){return c;} static char_type to_char_type(int_type c){return static_cast<char_type>(c);} static bool eq_int_type(int_type a,int_type b){return a==b;} static int_type eof(){return -1;} static int_type not_eof(int_type c){return c==eof()?0:c;}\n"
            "};\n}\n", required=False)
    # The traits specializations must be visible before libc++ parses
    # basic_string's dependent machinery; move the compatibility block ahead
    # of <string> after the textual insertion above.
    converter = work / "src/encode_converter.h"
    text = converter.read_text()
    match = re.search(r"#include <vector>\n(namespace std \{.*?\n\})\n\n#ifdef _MSC_VER", text, re.S)
    if match:
        traits = match.group(1)
        text = text[:match.start()] + "#include <vector>\n" + text[match.end()-len("\n\n#ifdef _MSC_VER"):]
        text = text.replace("#include <string>", "#include <string>\n" + traits, 1)
        converter.write_text(text)


def patch_all(config) -> None:
    speech_sources = config.speech / ".build-deps/sources"
    ocr_sources = config.ocr / ".build-deps/sources"
    patch_onnxruntime(speech_sources / "onnxruntime-v1.22.0")
    patch_piper(speech_sources / "piper-404aefedbd74baa0bd43e451bc407a2b3aace0f5",
                config.speech / ".build-deps" / config.target / "piper-source")
    patch_funasr(speech_sources / "funasr-231ec5dda739c83f35e59e875736cde3ef1af161/runtime/onnxruntime",
                 config.speech / ".build-deps" / config.target / "funasr-source")
