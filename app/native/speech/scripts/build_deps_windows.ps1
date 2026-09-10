$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$SpeechDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BuildRoot = Join-Path $SpeechDir ".build-deps\windows-x64"
$SourceRoot = Join-Path $SpeechDir ".build-deps\sources"
$Vendor = Join-Path $SpeechDir "vendor\windows-x64"
$PiperCommit = "404aefedbd74baa0bd43e451bc407a2b3aace0f5"
$FunAsrCommit = "231ec5dda739c83f35e59e875736cde3ef1af161"
$OrtTag = "v1.22.0"
$OrtRevision = "f217402897f40ebba457e2421bc0a4702771968e"

New-Item -ItemType Directory -Force -Path $BuildRoot, $SourceRoot, "$Vendor\include", "$Vendor\lib" | Out-Null

function Resolve-GitCommit([string]$Destination, [string]$Revision) {
  $PreviousNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
  try {
    $PSNativeCommandUseErrorActionPreference = $false
    $Result = git -C $Destination rev-parse --verify "$Revision^{commit}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $Result) {
      return $Result.Trim()
    }
    return $null
  } finally {
    $PSNativeCommandUseErrorActionPreference = $PreviousNativeErrorPreference
  }
}

function Checkout-Revision([string]$Url, [string]$Revision, [string]$Destination) {
  if (-not (Test-Path "$Destination\.git")) {
    git init -q $Destination
    git -C $Destination remote add origin $Url
  }
  $Current = Resolve-GitCommit $Destination "HEAD"
  $Expected = Resolve-GitCommit $Destination $Revision
  if (-not $Expected) {
    git -C $Destination fetch --depth 1 origin $Revision
    $Expected = Resolve-GitCommit $Destination "FETCH_HEAD"
    if (-not $Expected) { throw "Failed to resolve revision $Revision" }
  }
  if ($Current -ne $Expected) {
    git -C $Destination checkout -q --detach $Expected
  }
}

$OrtSource = Join-Path $SourceRoot "onnxruntime-$OrtTag"
$PiperSource = Join-Path $SourceRoot "piper-$PiperCommit"
$FunAsrSource = Join-Path $SourceRoot "funasr-$FunAsrCommit"
Checkout-Revision "https://github.com/microsoft/onnxruntime.git" $OrtRevision $OrtSource
Checkout-Revision "https://github.com/OHF-Voice/piper1-gpl.git" $PiperCommit $PiperSource
Checkout-Revision "https://github.com/modelscope/FunASR.git" $FunAsrCommit $FunAsrSource

$OrtDeps = "$OrtSource\cmake\deps.txt"
(Get-Content $OrtDeps -Raw).Replace(
  "5ea4d05e62d7f954a46b3213f9b2535bdd866803",
  "51982be81bbe52572b54180454df11a3ece9a934"
) | Set-Content $OrtDeps

$OptimizerApi = "$OrtSource\onnxruntime\core\optimizer\transpose_optimization\optimizer_api.h"
$OptimizerApiContents = Get-Content $OptimizerApi -Raw
if ($OptimizerApiContents -notmatch '#include <cstdint>') {
  $OptimizerApiContents.Replace(
    "#include <functional>",
    "#include <cstdint>`r`n#include <functional>"
  ) | Set-Content $OptimizerApi
}

$OrtBuild = Join-Path $BuildRoot "onnxruntime"
if (-not (Test-Path "$BuildRoot\onnxruntime.done")) {
  & "$OrtSource\build.bat" --config Release --build_dir $OrtBuild --parallel --skip_tests --compile_no_warning_as_error
  New-Item -ItemType File -Force "$BuildRoot\onnxruntime.done" | Out-Null
}
Copy-Item "$OrtSource\include\onnxruntime\core\session\*.h" "$Vendor\include" -Force

$OrtLibs = @(Get-ChildItem $OrtBuild -Recurse -File -Filter "*.lib" | Where-Object {
  $_.FullName -match "Release" -and $_.Name -notmatch "test|benchmark"
})
if ($OrtLibs.Count -eq 0) { throw "No static ONNX Runtime libraries found" }
& lib.exe /NOLOGO /OUT:"$Vendor\lib\onnxruntime.lib" @($OrtLibs.FullName)

$PiperWork = Join-Path $BuildRoot "piper-source"
if (Test-Path $PiperWork) { Remove-Item -Recurse -Force $PiperWork }
Copy-Item "$PiperSource\libpiper" $PiperWork -Recurse
Copy-Item "$PiperSource\setup.py" "$BuildRoot\setup.py" -Force
$PiperCmake = "$PiperWork\CMakeLists.txt"
(Get-Content $PiperCmake -Raw).Replace(
  "cmake_minimum_required(VERSION 3.26)", "cmake_minimum_required(VERSION 3.16)"
).Replace("add_library(piper SHARED", "add_library(piper STATIC") | Set-Content $PiperCmake
$PiperPhonemizer = Join-Path $PiperWork "src\chinese_phonemizer.cpp"
$PiperPhonemizerContents = Get-Content $PiperPhonemizer -Raw
$PatchedPiperPhonemizer = $PiperPhonemizerContents `
  -replace '(?m)^  bool first_syl = true;\r?\n', '' `
  -replace '(?ms)^    if \(!first_syl\) \{\r?\n      // optional short pause between syllables\r?\n      phonemes\.push_back\(" "\);\r?\n    \}\r?\n    first_syl = false;\r?\n\r?\n', ''
if ($PatchedPiperPhonemizer -eq $PiperPhonemizerContents -or
    $PatchedPiperPhonemizer.Contains('phonemes.push_back(" ");')) {
  throw "Failed to patch Piper pinyin whitespace handling"
}
Set-Content $PiperPhonemizer $PatchedPiperPhonemizer -NoNewline
cmake -S $PiperWork -B "$BuildRoot\piper" -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF `
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DONNXRUNTIME_DIR="$Vendor"
cmake --build "$BuildRoot\piper" --parallel

$FunAsrWork = Join-Path $BuildRoot "funasr-source"
if (Test-Path $FunAsrWork) { Remove-Item -Recurse -Force $FunAsrWork }
if (Test-Path "$BuildRoot\funasr") { Remove-Item -Recurse -Force "$BuildRoot\funasr" }
if (Test-Path "$Vendor\include\funasrruntime.h") { Remove-Item -Force "$Vendor\include\funasrruntime.h" }
Copy-Item "$FunAsrSource\runtime\onnxruntime" $FunAsrWork -Recurse
$OpenFstHeader = "$FunAsrWork\third_party\openfst\src\include\fst\fst.h"
(Get-Content $OpenFstHeader -Raw).Replace(
  "isymbols_ = impl.isymbols_ ? impl.isymbols_->Copy() : nullptr;",
  "isymbols_.reset(impl.isymbols_ ? impl.isymbols_->Copy() : nullptr);"
).Replace(
  "osymbols_ = impl.osymbols_ ? impl.osymbols_->Copy() : nullptr;",
  "osymbols_.reset(impl.osymbols_ ? impl.osymbols_->Copy() : nullptr);"
) | Set-Content $OpenFstHeader
$OpenFstBiTable = "$FunAsrWork\third_party\openfst\src\include\fst\bi-table.h"
(Get-Content $OpenFstBiTable -Raw).Replace(
  "new S(table.s_)",
  "new S(*table.selector_)"
) | Set-Content $OpenFstBiTable
$FbankRfft = "$FunAsrWork\third_party\kaldi-native-fbank\kaldi-native-fbank\csrc\rfft.h"
(Get-Content $FbankRfft -Raw).Replace(
  "#include <memory>",
  "#include <cstdint>`r`n#include <memory>"
) | Set-Content $FbankRfft
$FunAsrUtil = "$FunAsrWork\src\util.h"
$FunAsrUtilContents = Get-Content $FunAsrUtil -Raw
if ($FunAsrUtilContents -notmatch '#include <cstdint>') {
  "#include <cstdint>`r`n$FunAsrUtilContents" | Set-Content $FunAsrUtil
}
$FunAsrCmake = "$FunAsrWork\src\CMakeLists.txt"
(Get-Content $FunAsrCmake -Raw).Replace(
  "add_library(funasr SHARED", "add_library(funasr STATIC"
) | Set-Content $FunAsrCmake
cmake -S $FunAsrWork -B "$BuildRoot\funasr" -G Ninja `
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF `
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON `
  -DCMAKE_CXX_STANDARD=17 `
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 `
  -DONNXRUNTIME_DIR="$Vendor" `
  -DENABLE_FFMPEG=OFF -DFUNASR_BUILD_TESTS=OFF
cmake --build "$BuildRoot\funasr" --target funasr --parallel

Copy-Item "$PiperWork\include\piper.h" "$Vendor\include" -Force
Copy-Item "$FunAsrWork\include\funasrruntime.h" "$Vendor\include" -Force
$DependencyLibs = @("$Vendor\lib\onnxruntime.lib")
$DependencyLibs += @(Get-ChildItem "$BuildRoot\piper", "$BuildRoot\funasr" -Recurse -File -Filter "*.lib" | Where-Object {
  $_.Name -notmatch "test|benchmark"
} | ForEach-Object { $_.FullName })
& lib.exe /NOLOGO /OUT:"$Vendor\lib\zh_speech_deps.lib" @DependencyLibs

Write-Host "Static speech dependencies installed in $Vendor"
