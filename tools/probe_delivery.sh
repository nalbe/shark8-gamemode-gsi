#!/system/bin/sh
# Why did the watcher see no focus events? Isolate: (a) the field parse on a
# synthetic line, (b) logcat -> FIFO delivery.

line='09-21 16:11:10.026  2160  2303 I input_focus: [Focus entering 7660c3 com.android.settings/com.android.settings.Settings (server),reason=Window became focusable. Previous reason: NOT_VISIBLE]'
case "$line" in
    *"Focus entering "*" (server),"*) echo "parse-case: match" ;;
    *) echo "parse-case: NOMATCH" ;;
esac
set -- $line
echo "parse-fields: ev=$8 comp=$10"
pkg=${10%%/*}
echo "parse-pkg: $pkg"

rm -f /data/local/tmp/dbg.fifo /data/local/tmp/dbg.out
mkfifo /data/local/tmp/dbg.fifo
logcat -b events -s input_focus:V > /data/local/tmp/dbg.fifo 2>/dev/null &
LP=$!
(
    while read -r l; do
        echo "GOT $l" >> /data/local/tmp/dbg.out
    done < /data/local/tmp/dbg.fifo
) &
RP=$!
sleep 2
am start -n com.android.settings/.Settings >/dev/null 2>&1
sleep 3
input keyevent KEYCODE_HOME
sleep 3
kill $LP 2>/dev/null
sleep 1
kill $RP 2>/dev/null

echo "=== reader got: $(wc -l < /data/local/tmp/dbg.out 2>/dev/null) lines"
cat /data/local/tmp/dbg.out 2>/dev/null | tail -6
echo "=== buffer really has them (independent dump):"
logcat -b events -d -s input_focus:V | tail -3
echo "=== done"
