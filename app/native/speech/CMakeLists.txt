cmake_minimum_required(VERSION 3.16)
project(zh_speech LANGUAGES C CXX)

set(ZH_SPEECH_LIBRARY_TYPE "SHARED" CACHE STRING
    "Build zh_speech as SHARED or STATIC")

if(NOT ZH_SPEECH_VENDOR_ROOT)
  if(ANDROID)
    set(ZH_SPEECH_VENDOR_ROOT
        "${CMAKE_CURRENT_SOURCE_DIR}/vendor/android-${ANDROID_ABI}")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(ZH_SPEECH_VENDOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/ios-arm64")
  elseif(WIN32)
    set(ZH_SPEECH_VENDOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/windows-x64")
  elseif(APPLE)
    set(ZH_SPEECH_VENDOR_ROOT
        "${CMAKE_CURRENT_SOURCE_DIR}/vendor/macos-${CMAKE_SYSTEM_PROCESSOR}")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND
         CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
    set(ZH_SPEECH_VENDOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/linux-x64")
  else()
    message(FATAL_ERROR "Unsupported speech target; set ZH_SPEECH_VENDOR_ROOT")
  endif()
endif()

if(WIN32)
  set(ZH_SPEECH_DEPS "${ZH_SPEECH_VENDOR_ROOT}/lib/zh_speech_deps.lib")
else()
  set(ZH_SPEECH_DEPS "${ZH_SPEECH_VENDOR_ROOT}/lib/libzh_speech_deps.a")
endif()
if(NOT EXISTS "${ZH_SPEECH_DEPS}")
  message(FATAL_ERROR
    "Static speech dependencies are missing at ${ZH_SPEECH_DEPS}. "
    "Run native/speech/scripts/build_deps_* first.")
endif()

add_library(zh_speech ${ZH_SPEECH_LIBRARY_TYPE} speech_bridge.cpp)
target_compile_features(zh_speech PRIVATE cxx_std_17)
target_compile_definitions(zh_speech PRIVATE BUILDING_LIBPIPER)
target_include_directories(zh_speech PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${ZH_SPEECH_VENDOR_ROOT}/include"
)
if(MSVC)
  target_compile_options(zh_speech PRIVATE /EHsc /bigobj)
else()
  target_compile_options(zh_speech PRIVATE -fexceptions)
endif()
set_target_properties(zh_speech PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  POSITION_INDEPENDENT_CODE YES
)
target_link_libraries(zh_speech PRIVATE "${ZH_SPEECH_DEPS}")
if(CMAKE_SYSTEM_NAME STREQUAL "Linux" OR ANDROID)
  target_link_options(zh_speech PRIVATE "LINKER:-z,noexecstack")
endif()
if(UNIX AND NOT APPLE AND NOT ANDROID)
  target_link_libraries(zh_speech PRIVATE m pthread dl)
elseif(ANDROID)
  target_link_libraries(zh_speech PRIVATE log android atomic m)
elseif(WIN32)
  target_link_libraries(zh_speech PRIVATE dxcore)
elseif(APPLE)
  target_link_libraries(zh_speech PRIVATE
    "-framework Foundation" "-framework CoreFoundation" "-framework Accelerate")
endif()
