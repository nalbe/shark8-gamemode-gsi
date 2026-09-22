#!/system/bin/sh
# service.sh - KernelSU module entry point.
#
# Gamemode is manual: the event-driven watcher starts only when
# persist.shark8.gamemode.enable=1, which is what "gamemode.sh enable" sets.
# With the flag at 0 (default) this module does nothing at boot at all.

MODDIR=${0%/*}

# The helpers must be started from /data/local/tmp (unrestricted linker
# namespace, see gamemode.sh), so stage them there first.
BIN=/data/local/tmp/bin
mkdir -p "$BIN" 2>/dev/null
for b in powercli focuslog; do
    [ -f "$MODDIR/bin/$b" ] || exit 0
    cp -f "$MODDIR/bin/$b" "$BIN/$b" 2>/dev/null
    chmod 755 "$BIN/$b" 2>/dev/null
done

[ "$(getprop persist.shark8.gamemode.enable)" = "1" ] || exit 0

nohup sh "$MODDIR/gamemode.sh" watch >/dev/null 2>&1 &
