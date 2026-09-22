# Push the module to the device and set permissions. Nothing is started:
# gamemode is manual (gamemode.sh enable|on). A reboot is still required for
# KernelSU to pick the module up at boot.
#
#   powershell -File scripts/install.ps1

# Native tools (adb) write progress to stderr; keep that from being fatal.
$ErrorActionPreference = 'Continue'

$root   = Split-Path -Parent $PSScriptRoot
$adb    = 'D:\System\Apps\android-sdk\platform-tools\adb.exe'
$serial = 'SHARK8RU0006472'
$id     = 'shark8_gamemode'
$dev    = "/data/adb/modules/$id"

function Adb([string[]]$argv) {
    & $adb -s $serial @argv 2>&1 | ForEach-Object { "$_" } | Write-Host
    $rc = $LASTEXITCODE
    if ($rc -ne 0) { throw "adb failed ($rc): $($argv -join ' ')" }
}

Adb @('shell', "mkdir -p $dev/bin")
foreach ($f in 'module.prop', 'service.sh', 'gamemode.sh') {
    Adb @('push', (Join-Path $root "module\$f"), "$dev/$f")
}
foreach ($b in 'powercli', 'focuslog') {
    Adb @('push', (Join-Path $root "module\bin\$b"), "$dev/bin/$b")
}

Adb @('shell', "chmod 755 $dev/service.sh $dev/gamemode.sh $dev/bin/powercli $dev/bin/focuslog")
Adb @('shell', "chmod 644 $dev/module.prop")

# The engine reads /data/vendor/powerhal/power_app_cfg.xml in preference to the
# stock /vendor/etc table (both paths are in libpowerhal.so). Install our copy
# there: stock 40 entries plus the extra games listed in module/etc.
Adb @('push', (Join-Path $root 'module\etc\power_app_cfg.xml'), '/data/vendor/powerhal/power_app_cfg.xml')
Adb @('shell', 'chown system:system /data/vendor/powerhal/power_app_cfg.xml')
Adb @('shell', 'chmod 644 /data/vendor/powerhal/power_app_cfg.xml')

Adb @('shell', "sh $dev/gamemode.sh status")
Write-Host "installed. enable with:"
Write-Host "  adb shell 'sh $dev/gamemode.sh enable'   # persistent watcher"
Write-Host "  adb shell 'sh $dev/gamemode.sh on'       # one-shot"
