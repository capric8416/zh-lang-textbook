$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$OcrRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$DepsRoot = Join-Path $OcrRoot ".build-deps"
$SourceRoot = Join-Path $DepsRoot "sources"
$BuildRoot = Join-Path $DepsRoot "windows-x64"
$VendorRoot = Join-Path $OcrRoot "vendor/windows-x64"
$OpenCvSource = Join-Path $SourceRoot "opencv-4.11.0"
$NcnnSource = Join-Path $SourceRoot "ncnn-20241226"

New-Item -ItemType Directory -Force -Path $SourceRoot, $BuildRoot | Out-Null
if (-not (Test-Path (Join-Path $OpenCvSource ".git"))) {
  git clone --depth 1 --branch 4.11.0 https://github.com/opencv/opencv.git $OpenCvSource
}
if (-not (Test-Path (Join-Path $NcnnSource ".git"))) {
  git clone --depth 1 --branch 20241226 https://github.com/Tencent/ncnn.git $NcnnSource
}

if (Test-Path $VendorRoot) {
  cmake -E remove_directory $VendorRoot
}
New-Item -ItemType Directory -Force -Path $VendorRoot | Out-Null

$CommonArgs = @(
  "-G", "Visual Studio 17 2022",
  "-A", "x64",
  "-DCMAKE_POLICY_VERSION_MINIMUM=3.5",
  "-DCMAKE_INSTALL_PREFIX=$VendorRoot",
  "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
  "-DBUILD_SHARED_LIBS=OFF"
)

cmake -S $NcnnSource -B (Join-Path $BuildRoot "ncnn") @CommonArgs `
  -DNCNN_VERSION=20241226 `
  -DNCNN_SHARED_LIB=OFF `
  -DNCNN_OPENMP=ON `
  -DNCNN_VULKAN=OFF `
  -DNCNN_BUILD_TOOLS=OFF `
  -DNCNN_BUILD_EXAMPLES=OFF `
  -DNCNN_BUILD_BENCHMARK=OFF `
  -DNCNN_BUILD_TESTS=OFF
cmake --build (Join-Path $BuildRoot "ncnn") --config Release --parallel
cmake --install (Join-Path $BuildRoot "ncnn") --config Release

cmake -S $OpenCvSource -B (Join-Path $BuildRoot "opencv") @CommonArgs `
  -DBUILD_WITH_STATIC_CRT=OFF `
  "-DBUILD_LIST=core,imgproc,imgcodecs" `
  -DBUILD_opencv_apps=OFF `
  -DBUILD_opencv_java=OFF `
  -DBUILD_opencv_python2=OFF `
  -DBUILD_opencv_python3=OFF `
  -DBUILD_EXAMPLES=OFF `
  -DBUILD_PERF_TESTS=OFF `
  -DBUILD_TESTS=OFF `
  -DBUILD_DOCS=OFF `
  -DBUILD_PROTOBUF=OFF `
  -DWITH_PROTOBUF=OFF `
  -DWITH_FLATBUFFERS=OFF `
  -DOPENCV_FORCE_3RDPARTY_BUILD=ON `
  -DWITH_JPEG=ON `
  -DWITH_PNG=ON `
  -DWITH_ZLIB=ON `
  -DWITH_FFMPEG=OFF `
  -DWITH_GSTREAMER=OFF `
  -DWITH_OPENCL=OFF `
  -DWITH_OPENEXR=OFF `
  -DWITH_TIFF=OFF `
  -DWITH_WEBP=OFF `
  -DWITH_ITT=OFF `
  -DWITH_IPP=OFF `
  -DWITH_EIGEN=OFF `
  -DWITH_LAPACK=OFF
cmake --build (Join-Path $BuildRoot "opencv") --config Release --parallel
# OpenCV exports the optional ADE target even when G-API is excluded by
# BUILD_LIST. Build it explicitly so OpenCVModules.cmake has no missing archive.
cmake --build (Join-Path $BuildRoot "opencv") --config Release --target ade --parallel
cmake --install (Join-Path $BuildRoot "opencv") --config Release

Write-Host "Static OCR dependencies installed in $VendorRoot"
