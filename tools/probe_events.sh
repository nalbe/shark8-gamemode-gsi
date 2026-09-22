#!/system/bin/sh
# Are the AMS activity events usable as a push source on this GSI?
# (the events buffer itself is flooded by auditd, so only a live reader can
#  tell - a -d dump shows nothing but audit lines)
logcat -b events -s am_focused_activity:V am_resume_activity:V am_pause_activity:V am_proc_start:V am_proc_died:V > /data/local/tmp/ev.txt 2>&1 &
LP=$!
sleep 2
am start -n com.android.settings/.Settings >/dev/null 2>&1
sleep 3
input keyevent KEYCODE_HOME
sleep 3
am start -n com.android.settings/.Settings >/dev/null 2>&1
sleep 3
kill $LP 2>/dev/null
echo "=== lines: $(wc -l < /data/local/tmp/ev.txt)"
cat /data/local/tmp/ev.txt
echo "=== done"
