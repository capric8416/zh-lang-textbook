cmake_minimum_required(VERSION 3.16)
project(piper_input_compare LANGUAGES CXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
  message(FATAL_ERROR "These comparison programs are Linux-only")
endif()

set(SPEECH_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(VENDOR_ROOT "${SPEECH_ROOT}/vendor/linux-x64" CACHE PATH
    "Linux static speech dependency directory")
set(SPEECH_DEPS "${VENDOR_ROOT}/lib/libzh_speech_deps.a")
if(NOT EXISTS "${SPEECH_DEPS}")
  message(FATAL_ERROR
    "Missing ${SPEECH_DEPS}; run native/speech/scripts/build_deps_unix.sh linux-x64")
endif()

find_package(Threads REQUIRED)

add_library(tts_compare_common STATIC tts_compare.cpp)
target_compile_features(tts_compare_common PUBLIC cxx_std_17)
target_include_directories(tts_compare_common PRIVATE "${VENDOR_ROOT}/include")
target_link_libraries(tts_compare_common PUBLIC
  "${SPEECH_DEPS}" Threads::Threads ${CMAKE_DL_LIBS} m)
target_link_options(tts_compare_common INTERFACE "LINKER:-z,noexecstack")

add_executable(piper_hanzi_linux piper_hanzi_linux.cpp)
target_link_libraries(piper_hanzi_linux PRIVATE tts_compare_common)

add_executable(piper_pinyin_linux piper_pinyin_linux.cpp)
target_link_libraries(piper_pinyin_linux PRIVATE tts_compare_common)
