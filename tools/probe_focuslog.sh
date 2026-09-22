#!/system/bin/sh
# Validate tools/focuslog.c against the real events buffer:
#  - nothing is replayed at start (the buffer is full of auditd spam)
#  - one short line per focus change, matching logcat's view
#
#   sh /data/local/tmp/probe_focuslog.sh
#
# Needs /data/local/tmp/bin/focuslog.

F=/data/local/tmp/fl.txt
E=/data/local/tmp/fl.err
rm -f "$F" "$E"
/data/local/tmp/bin/focuslog -v > "$F" 2> "$E" &
LP=$!
sleep 2
echo "--- lines right after start (must be 0): $(wc -l < "$F")"

am start -n com.android.settings/.Settings >/dev/null 2>&1
sleep 3
input keyevent KEYCODE_HOME
sleep 3
am start -n com.android.settings/.Settings >/dev/null 2>&1
sleep 3
kill $LP 2>/dev/null

echo "--- focuslog output ($(wc -l < "$F") lines)"
cat "$F"
echo "--- stderr"
cat "$E"
echo "--- logcat view of the same window"
logcat -b events -d -s input_focus:V | tail -6
echo "--- done"
