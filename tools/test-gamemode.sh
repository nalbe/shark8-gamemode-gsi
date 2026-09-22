#!/system/bin/sh
# End-to-end test of gamemode.sh against the installed module with a fake
# whitelist (none of the 40 stock entries are installed on this device).
# Proves: the input_focus event source (via bin/focuslog), the literal
# <Activity> lookup, apply/release and the one-shot on/off.
#
#   adb push tools/test-whitelist.xml /data/local/tmp/
#   adb push tools/test-gamemode.sh  /data/local/tmp/
#   adb shell 'sh /data/local/tmp/test-gamemode.sh'
#
# The device must NOT have an enabled persistent watcher running (this test
# starts its own and kills it again).

MOD=gamemode.sh
WL=/data/local/tmp/test-whitelist.xml
MAP=/data/local/tmp/gamemode-test.map
GLOG=/data/local/tmp/gamemode.log

[ -x /data/adb/modules/shark8_gamemode/bin/focuslog ] || {
    echo "module not installed (run scripts/install.ps1)"; exit 1
}
[ -f "$WL" ] || { echo "missing $WL"; exit 1; }

setprop persist.log.tag.libPowerHal I
setprop persist.log.tag.mtkpower@impl V
setprop ctl.restart power-hal-1-0
sleep 4

sh /data/adb/modules/shark8_gamemode/$MOD disable >/dev/null 2>&1
sleep 1
rm -f "$GLOG"

GAMEMODE_WL=$WL GAMEMODE_MAP=$MAP nohup sh /data/adb/modules/shark8_gamemode/$MOD watch >/dev/null 2>&1 &
sleep 4
echo "--- watcher startup"
tail -3 "$GLOG"

echo "--- switch to Settings (HOME first, so the focus really changes)"
input keyevent KEYCODE_HOME
sleep 2
am start -n com.android.settings/.Settings >/dev/null 2>&1
sleep 3
tail -3 "$GLOG"

echo "--- back to launcher"
input keyevent KEYCODE_HOME
sleep 3
tail -3 "$GLOG"

echo "--- one-shot off / on"
GAMEMODE_WL=$WL GAMEMODE_MAP=$MAP sh /data/adb/modules/shark8_gamemode/$MOD off
GAMEMODE_WL=$WL GAMEMODE_MAP=$MAP sh /data/adb/modules/shark8_gamemode/$MOD on

echo "--- status"
GAMEMODE_WL=$WL GAMEMODE_MAP=$MAP sh /data/adb/modules/shark8_gamemode/$MOD status

echo "--- literal <Activity> proof: stock entry 'Common' for a package that is"
echo "    not installed. The engine answers with a burst of [PE] <profile> lines."
logcat -d > /data/local/tmp/l.txt
before=$(grep -c PE] /data/local/tmp/l.txt)
/data/local/tmp/bin/powercli notify com.tencent.tmgp.sgame Common 4000 1 10000 2>&1
sleep 2
logcat -d > /data/local/tmp/l.txt
after=$(grep -c PE] /data/local/tmp/l.txt)
echo "PE lines before=$before after=$after"
grep PE] /data/local/tmp/l.txt | tail -5

echo "--- stop watcher"
kill $(head -1 /data/local/tmp/gamemode.pid) 2>/dev/null
sleep 1
tail -3 "$GLOG"
echo "--- done"
