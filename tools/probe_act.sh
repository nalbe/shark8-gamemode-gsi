#!/system/bin/sh
# Does the whitelist match depend on the activity string? sgame's entry in
# power_app_cfg.xml is <Activity name="Common">; feed the engine "Common",
# a bogus activity and the real one and count the applied profile lines.
setprop persist.log.tag.libPowerHal I
setprop persist.log.tag.mtkpower@impl V
setprop ctl.restart power-hal-1-0
sleep 4

try() {
  logcat -c
  sleep 1
  /data/local/tmp/powercli notify com.tencent.tmgp.sgame "$1" 2435 1 10202 >/dev/null
  sleep 2
  logcat -d > /data/local/tmp/lc-act.txt
  n=`grep -c 'PE. com.tencent.tmgp.sgame' /data/local/tmp/lc-act.txt`
  m=`grep -c perfNotifyAppState /data/local/tmp/lc-act.txt`
  d=`grep 'act =>' /data/local/tmp/lc-act.txt | tail -1`
  echo "act=$1 PE_lines=$n perfNotifyAppState=$m [$d]"
}

try Common
try com.foo.Bar
try com.tencent.tmgp.sgame.SGameActivity
echo "--- tail"
logcat -d | grep -e "act  =>" -e perfNotifyAppState | tail -6
echo "--- done"
