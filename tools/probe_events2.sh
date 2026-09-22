#!/system/bin/sh
# Raw live dump of the events buffer while switching apps, to find out which
# event tags this GSI actually writes (no -s filter: filter locally).
logcat -b events -v threadtime > /data/local/tmp/ev2.txt 2>&1 &
LP=$!
sleep 2
am start -n com.android.settings/.Settings >/dev/null 2>&1
sleep 3
input keyevent KEYCODE_HOME
sleep 3
am start -n com.android.settings/.Settings >/dev/null 2>&1
sleep 3
kill $LP 2>/dev/null

echo "=== total lines: $(wc -l < /data/local/tmp/ev2.txt)"
echo "=== auditd lines: $(grep -c auditd /data/local/tmp/ev2.txt)"
echo "=== tag histogram (non-auditd)"
grep -v auditd /data/local/tmp/ev2.txt | awk '{print $6}' | sort | uniq -c | sort -rn | head -20
echo "=== non-auditd tail"
grep -v auditd /data/local/tmp/ev2.txt | tail -25
echo "=== done"
