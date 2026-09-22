#!/system/bin/sh
setprop persist.log.tag.mtkpower@impl E
setprop persist.log.tag.libPowerHal E
setprop persist.log.tag.mtkpower_client E
setprop ctl.restart power-hal-1-0
sleep 4
echo "--- service"
ps -A | grep mtkpower
logcat -c
sleep 1
/data/local/tmp/powercli notify com.tencent.tmgp.sgame Common 2435 1 10202
sleep 2
logcat -d > /data/local/tmp/lc3.txt
echo "state1 log lines: `wc -l < /data/local/tmp/lc3.txt`"
echo "--- state1 engine lines"
grep -e powerhal -e PowerHal -e mtkpower /data/local/tmp/lc3.txt | head -40
logcat -c
sleep 1
/data/local/tmp/powercli notify com.tencent.tmgp.sgame Common 2435 0 10202
sleep 2
logcat -d > /data/local/tmp/lc4.txt
echo "state0 log lines: `wc -l < /data/local/tmp/lc4.txt`"
echo "--- state0 engine lines"
grep -e powerhal -e PowerHal -e mtkpower /data/local/tmp/lc4.txt | head -40
echo "--- done"
