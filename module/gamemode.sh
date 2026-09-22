#!/system/bin/sh
# gamemode.sh - trigger the stock MTK game profiles on a GSI. Event driven.
#
# The stock MTK framework told the vendor power HAL which package/activity is
# in the foreground through HIDL IMtkPower::notifyAppState(). An AOSP/PHH GSI
# replaces that framework, so /vendor/bin/hw/vendor.mediatek.hardware.mtkpower
# @1.0-service (init service "power-hal-1-0") never receives the trigger and
# the whitelist profiles in /vendor/etc/power_app_cfg.xml never apply.
#
# This script supplies exactly that trigger and nothing else. There is no
# polling and no logcat: bin/focuslog reads the logd events buffer through
# liblog's reader API, picks the WindowManager input_focus events out of it and
# prints one short line per real focus change
#
#   entering <pkg>/<act>
#   leaving <pkg>/<act>
#
# The watcher consumes that and only then talks to the HAL. With no focus
# change and no whitelisted package, it costs nothing.
#
# The <act> string MUST be the literal <Activity name="..."> value from the
# whitelist: the vendor engine compares it with strcmp (36 of 40 entries use
# the pseudo-activity "Common"). Any other string silently applies nothing.
#
# Subcommands:
#   watch     run the foreground watcher (event driven, no polling)
#   on        one-shot: boost whatever is in the foreground right now
#   off       one-shot: release whatever was boosted
#   enable    persist the flag and start the watcher now
#   disable   stop the watcher and clear the flag
#   status    print flag, watcher pid and the boosted app
#
# The flag is persist.shark8.gamemode.enable (0/1, default off): nothing runs
# at boot and nothing is watched unless it is 1. Gamemode is manual by design.
#
# Test hooks (see tools/test-gamemode.sh):
#   GAMEMODE_WL / GAMEMODE_MAP  env override of the whitelist and parsed map
#   persist.shark8.gamemode.wl  same for the boot-time watcher, which has no
#                               environment (point it at a custom whitelist)

MODDIR=${0%/*}

# The helpers must run from /data/local/tmp: /linkerconfig/ld.config.txt gives
# that one directory the "unrestricted" namespace (dir.unrestricted) whose
# search paths include /vendor/${LIB}. A binary started from anywhere else in
# /data lands in the isolated default namespace, where dlopen of
# /vendor/lib64/libpowerhalwrap_vendor.so fails with "not accessible for the
# namespace (default)". focuslog only needs liblog (/system/${LIB}), which both
# namespaces allow, but both are staged for uniformity.
BIN=/data/local/tmp/bin
stage() {
    mkdir -p "$BIN" 2>/dev/null
    for b in powercli focuslog; do
        s="$MODDIR/bin/$b"
        [ -f "$s" ] || continue
        if [ ! -x "$BIN/$b" ] || [ "$s" -nt "$BIN/$b" ]; then
            cp -f "$s" "$BIN/$b" 2>/dev/null
            chmod 755 "$BIN/$b" 2>/dev/null
        fi
    done
}
stage
CLI="$BIN/powercli"
[ -x "$CLI" ] || CLI="$MODDIR/bin/powercli"
FLOG="$BIN/focuslog"
[ -x "$FLOG" ] || FLOG="$MODDIR/bin/focuslog"
# Whitelist precedence, mirroring the engine's own (libpowerhal.so contains both
# paths): env override (tests) > persist.shark8.gamemode.wl > the updatable
# table in /data/vendor/powerhal > the stock table in /vendor/etc.
# module/etc/power_app_cfg.xml is installed to the /data/vendor/powerhal slot
# (see README: adding a game that is not in the vendor table).
WL=${GAMEMODE_WL:-$(getprop persist.shark8.gamemode.wl)}
if [ -z "$WL" ] || [ ! -f "$WL" ]; then
    WL=/vendor/etc/power_app_cfg.xml
    [ -r /data/vendor/powerhal/power_app_cfg.xml ] &&
        WL=/data/vendor/powerhal/power_app_cfg.xml
fi
MAP=${GAMEMODE_MAP:-/data/local/tmp/gamemode-whitelist.map}
PIDF=/data/local/tmp/gamemode.pid
STATE=/data/local/tmp/gamemode.state
FIFO=/data/local/tmp/gamemode.fifo
LOG=/data/local/tmp/gamemode.log
FLAG=persist.shark8.gamemode.enable

# logcat is not always usable at boot, so the same lines also go to a small
# plain file (rotated at every watcher start).
log_() {
    log -t gamemode "$@"
    echo "$(date '+%m-%d %H:%M:%S') $$ $*" >> "$LOG" 2>/dev/null
}

rotate_log() {
    [ -s "$LOG" ] || return 0
    tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
}

# package -> activity-string table parsed from the stock whitelist
parse_wl() {
    awk -F'"' '/<Package name=/{pkg=$2} /<Activity name=/{if (pkg != "") {print pkg" "$2; pkg=""}}' \
        "$WL" > "$MAP" 2>/dev/null
    [ -s "$MAP" ]
}

# $1 = package; prints the whitelisted activity string (empty if not listed)
wl_act() {
    while read -r p a; do
        if [ "$p" = "$1" ]; then
            echo "$a"
            return
        fi
    done < "$MAP"
}

# $1 = package; prints the main pid (empty if the process is not up yet)
find_pid() {
    p=$(pidof "$1" 2>/dev/null)
    [ -n "$p" ] || p=$(pgrep -f "$1" 2>/dev/null | head -1)
    set -- $p
    echo "$1"
}

boosted() { cut -d' ' -f1 "$STATE" 2>/dev/null; }

# true if the watcher recorded in the pidfile is still alive
watcher_alive() {
    [ -f "$PIDF" ] || return 1
    while read -r p; do
        kill -0 "$p" 2>/dev/null && return 0
    done < "$PIDF"
    return 1
}

# $1 = package; waits up to 5s for the process, then notifies state=1
apply() {
    a=$(wl_act "$1")
    [ -n "$a" ] || return 0
    i=0
    p=""
    while [ $i -lt 10 ]; do
        p=$(find_pid "$1")
        [ -n "$p" ] && break
        sleep 0.5
        i=$((i + 1))
    done
    if [ -z "$p" ]; then
        log_ "miss $1 act=$a (no pid)"
        return 1
    fi
    u=$(stat -c %u "/proc/$p" 2>/dev/null)
    "$CLI" notify "$1" "$a" "$p" 1 "$u" >/dev/null 2>&1
    echo "$1 $a $p $u" > "$STATE"
    log_ "apply $1 act=$a pid=$p uid=$u"
}

release() {
    set -- $(cat "$STATE" 2>/dev/null)
    [ -n "$1" ] || return 0
    "$CLI" notify "$1" "$2" "$3" 0 "$4" >/dev/null 2>&1
    log_ "release $1 act=$2"
    rm -f "$STATE"
}

# one-shot foreground lookup (a single binder call; not used by the watcher)
fg_pkg() {
    dumpsys activity activities 2>/dev/null \
        | grep -m1 ResumedActivity \
        | sed -n 's/.* u[0-9]* \([^ ]*\) .*/\1/p' \
        | sed 's#/.*##'
}

watch() {
    [ -x "$FLOG" ] || { log_ "fatal: $FLOG missing"; exit 1; }
    parse_wl || { log_ "fatal: cannot parse $WL"; exit 1; }
    rotate_log
    log_ "watch start pid=$$ packages=$(wc -l < "$MAP")"
    echo "$$" > "$PIDF"
    rm -f "$FIFO"
    mkfifo "$FIFO"
    # focuslog starts at "now", so the stale events already in the buffer are
    # never replayed and are never acted upon.
    "$FLOG" > "$FIFO" 2>>"$LOG.err" &
    lgp=$!
    echo "$lgp" >> "$PIDF"
    trap 'kill "$lgp" 2>/dev/null; rm -f "$FIFO" "$PIDF"; log_ "watch stop (signal)"; exit 0' TERM INT HUP

    while read -r ev comp; do
        case "$comp" in */*) ;; *) continue ;; esac
        pkg=${comp%%/*}
        cur=$(boosted)
        case "$ev" in
            entering)
                [ "$pkg" = "$cur" ] && continue
                [ -n "$cur" ] && release
                apply "$pkg"
                ;;
            leaving)
                [ "$pkg" = "$cur" ] && release
                ;;
        esac
    done < "$FIFO"

    kill "$lgp" 2>/dev/null
    rm -f "$FIFO" "$PIDF"
    log_ "watch stop (reader gone)"
}

stop_watch() {
    if watcher_alive; then
        while read -r p; do
            kill "$p" 2>/dev/null
        done < "$PIDF"
        sleep 1
    fi
    rm -f "$PIDF" "$FIFO"
}

case "$1" in
    watch) watch ;;
    on)
        parse_wl || exit 1
        p=$(fg_pkg)
        [ -n "$p" ] || { echo "no resumed activity"; exit 1; }
        apply "$p"
        ;;
    off) release ;;
    enable)
        setprop "$FLAG" 1
        if ! watcher_alive; then
            rm -f "$PIDF" "$FIFO"
            nohup sh "$0" watch >/dev/null 2>&1 &
            sleep 1
        fi
        echo "enabled $(getprop "$FLAG")"
        cat "$STATE" 2>/dev/null
        ;;
    disable)
        setprop "$FLAG" 0
        stop_watch
        release
        echo "disabled $(getprop "$FLAG")"
        ;;
    status)
        f=$(getprop "$FLAG")
        echo "flag=${f:-0} (0=off 1=watch at boot)"
        if watcher_alive; then
            echo "watcher=running pid $(tr '\n' ' ' < "$PIDF")"
        else
            echo "watcher=stopped"
        fi
        echo "boosted=$(cat "$STATE" 2>/dev/null)"
        ;;
    *)
        echo "usage: gamemode.sh watch|on|off|enable|disable|status"
        exit 2
        ;;
esac
