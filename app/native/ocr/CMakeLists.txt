cmake_minimum_required(VERSION 3.16)
project(zh_ocr LANGUAGES CXX)

set(ZH_OCR_LIBRARY_TYPE "SHARED" CACHE STRING "Build zh_ocr as SHARED or STATIC")
option(ZH_OCR_USE_OPENMP "Use OpenMP for OCR inference" ON)

if(NOT ZH_OCR_VENDOR_ROOT)
  if(ANDROID)
    set(ZH_OCR_VENDOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/android-${ANDROID_ABI}")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(ZH_OCR_VENDOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/ios-arm64")
  elseif(WIN32)
    set(ZH_OCR_VENDOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/windows-x64")
  elseif(APPLE)
    set(ZH_OCR_VENDOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/macos-${CMAKE_SYSTEM_PROCESSOR}")
  elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
    set(ZH_OCR_VENDOR_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/vendor/linux-x64")
  else()
    message(FATAL_ERROR
      "No OCR native dependencies for ${CMAKE_SYSTEM_NAME}/${CMAKE_SYSTEM_PROCESSOR}. "
      "Set ZH_OCR_VENDOR_ROOT to a directory containing include/ and lib/.")
  endif()
endif()

set(OCR_SOURCES
  ocr_bridge.cpp
  src/db_net.cpp
  src/angle_net.cpp
  src/crnn_net.cpp
  src/ocr_engine.cpp
  src/utils.cpp
  src/3rdparty/clipper2/clipper.engine.cpp
  src/3rdparty/clipper2/clipper.offset.cpp
  src/3rdparty/clipper2/clipper.rectclip.cpp
)

add_library(zh_ocr ${ZH_OCR_LIBRARY_TYPE} ${OCR_SOURCES})
target_compile_features(zh_ocr PRIVATE cxx_std_17)
if(MSVC)
  set_source_files_properties(${OCR_SOURCES} PROPERTIES COMPILE_OPTIONS /EHsc)
else()
  # Some Android/iOS dependency targets propagate -fno-exceptions after
  # target-level options. Source options are emitted last, and these sources
  # require exceptions for JSON parsing and the FFI safety boundary.
  set_source_files_properties(${OCR_SOURCES} PROPERTIES COMPILE_OPTIONS -fexceptions)
endif()
set_target_properties(zh_ocr PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES
  POSITION_INDEPENDENT_CODE YES
)

target_include_directories(zh_ocr PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/3rdparty"
  "${ZH_OCR_VENDOR_ROOT}/include"
  "${ZH_OCR_VENDOR_ROOT}/include/ncnn"
  "${ZH_OCR_VENDOR_ROOT}/include/opencv4"
)

file(GLOB_RECURSE NCNN_CONFIGS "${ZH_OCR_VENDOR_ROOT}/*ncnnConfig.cmake")
file(GLOB_RECURSE OPENCV_CONFIGS "${ZH_OCR_VENDOR_ROOT}/*OpenCVConfig.cmake")

if(NCNN_CONFIGS AND OPENCV_CONFIGS)
  list(GET NCNN_CONFIGS 0 NCNN_CONFIG)
  list(GET OPENCV_CONFIGS 0 OPENCV_CONFIG)
  get_filename_component(ncnn_DIR "${NCNN_CONFIG}" DIRECTORY)
  get_filename_component(OpenCV_DIR "${OPENCV_CONFIG}" DIRECTORY)
  set(OpenCV_STATIC ON)
  find_package(ncnn CONFIG REQUIRED NO_DEFAULT_PATH PATHS "${ncnn_DIR}")
  find_package(OpenCV 4.11 CONFIG REQUIRED COMPONENTS core imgproc imgcodecs
    NO_DEFAULT_PATH PATHS "${OpenCV_DIR}")
  target_include_directories(zh_ocr PRIVATE ${OpenCV_INCLUDE_DIRS})
  target_link_libraries(zh_ocr PRIVATE ncnn ${OpenCV_LIBS} ${CMAKE_DL_LIBS})
else()
  # Backward-compatible fallback for the original manually copied Linux bundle.
  target_link_libraries(zh_ocr PRIVATE
    "${ZH_OCR_VENDOR_ROOT}/lib/libncnn.a"
    "${ZH_OCR_VENDOR_ROOT}/lib/libopencv_imgcodecs.a"
    "${ZH_OCR_VENDOR_ROOT}/lib/libopencv_imgproc.a"
    "${ZH_OCR_VENDOR_ROOT}/lib/libopencv_core.a"
    "${ZH_OCR_VENDOR_ROOT}/lib/liblibjpeg-turbo.a"
    "${ZH_OCR_VENDOR_ROOT}/lib/liblibpng.a"
    "${ZH_OCR_VENDOR_ROOT}/lib/libzlib.a"
    ${CMAKE_DL_LIBS}
  )
endif()

if(ZH_OCR_USE_OPENMP)
  find_package(OpenMP REQUIRED)
  target_link_libraries(zh_ocr PRIVATE OpenMP::OpenMP_CXX)
endif()

if(UNIX AND NOT APPLE)
  target_link_libraries(zh_ocr PRIVATE m pthread rt)
endif()
