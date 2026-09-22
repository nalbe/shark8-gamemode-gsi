# Build tools/*.c into module/bin/ with the NDK (aarch64, API 21).
#
#   powershell -File scripts/build.ps1
#
# Both binaries are self-contained apart from libdl/libc (bionic):
#   powercli  talks to the vendor HIDL power HAL through
#             /vendor/lib64/libpowerhalwrap_vendor.so (dlopen)
#   focuslog  reads the logd events buffer through liblog's reader API (dlopen)

# clang may write warnings to stderr; keep that from being fatal.
$ErrorActionPreference = 'Continue'

$root    = Split-Path -Parent $PSScriptRoot
$ndk     = 'D:\System\Apps\Android NDK\android-ndk-r27d'
$bin     = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$sysroot = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\sysroot'
foreach ($name in 'powercli', 'focuslog') {
    $out = Join-Path $root "module\bin\$name"
    $src = Join-Path $root "tools\$name.c"
    & "$bin\clang.exe" --target=aarch64-linux-android21 --sysroot="$sysroot" `
        -fPIE -pie -O2 -Wall -Wextra -o "$out" "$src" -ldl
    if (-not $?) { throw "clang failed: $name" }
    Write-Host ("built: {0} ({1} bytes)" -f $out, (Get-Item -LiteralPath $out).Length)
}
