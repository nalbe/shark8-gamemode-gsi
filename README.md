# shark8-gamemode-gsi

KernelSU module + diagnostic kit that gives the Blackview Shark 8 (Helio
G99 / mt6789, AOSP/PHH GSI over the stock MTK vendor image) its stock MTK game
mode back.

The vendor power engine and its tables are all still there and fully
functional - what a GSI removes is the *trigger*: the MTK framework call that
told the engine "package X, activity Y is now in the foreground". This project
re-supplies that trigger, so the stock profiles in
`/vendor/etc/power_app_cfg.xml` (40 whitelisted packages) apply again.

Pure trigger. No binary patches, no overlay of our own, no DVFS policy of our
own - the vendor engine does the work with the vendor tables.

Tested on: SHARK8RU0006472, AOSP GSI TP1A.220624.014 (user build) + KernelSU
0.9.4, stock vendor image.

Related, deliberately separate project:
[shark8-gsi-logspam-cosmetics](../shark8-gsi-logspam-cosmetics) owns every
binary patch of the vendor power stack (and the `persist.log.tag.*` props).
This project must never ship an overlay for a file that project patches -
one owner per file.

## The gap

* `power-hal-1-0` (`/vendor/bin/hw/vendor.mediatek.hardware.mtkpower@1.0-service`)
  hosts the AIDL `IPower` HAL, the HIDL `IMtkPower`/`IMtkPerf` servers and, in
  process, the real engine `libpowerhal.so`.
* The engine reads `/vendor/etc/{power_app_cfg.xml,powerscntbl.xml,powercontable.xml}`
  itself and applies a full per-app profile (FPSGO, FBT, GBE, uclamp, DRAM OPP,
  thermal policy, net boost, GPU opp) as soon as it is told which app/activity
  is resumed.
* That "tell" came from the MTK framework (`ActivityManager` hooks in the stock
  `framework.jar`/`boot.oat`). A GSI replaces the framework, the hook is gone,
  the engine sits at idle forever.

There is no vendor node, no sysfs file and no property for this - the only
entry point is HIDL `IMtkPower::notifyAppState()`. For a game that is missing
from the vendor table, the same mechanism also accepts an updatable copy of that
table - see "Adding a game that is not in the vendor table".

## How it works

```
service.sh -> gamemode.sh watch -> bin/focuslog -> liblog reader API (events buffer)
                    |                                    |
                    | entering/leaving <pkg>/<act>       | WindowManager input_focus events
                    v                                    v
              bin/powercli -> libpowerhalwrap_vendor.so -> IMtkPower::notifyAppState
                    v
              libpowerhal.so -> vendor tables -> sysfs
```

`gamemode.sh watch` is event driven - **no polling**. The events buffer carries
one entry per real focus change:

```
I input_focus: [Focus entering a1243f5 com.pkg/com.pkg.Act (server),reason=...]
I input_focus: [Focus leaving  a1243f5 com.pkg/com.pkg.Act (server),reason=...]
```

`bin/focuslog` reads that buffer through liblog (`android_logger_open` +
`android_logger_list_read`, all `dlopen`ed from `/system/lib64/liblog.so`) and
reduces each entry to one short line:

```
entering com.pkg/com.pkg.Act
leaving com.pkg/com.pkg.Act
```

Why not `logcat`: (a) `-T n` counts *raw* lines before `-s` filtering, so on a
buffer flooded with auditd noise it prints nothing at all - the first boot-time
watcher silently received zero events because of this; (b) without `-T`,
`logcat` first replays the whole buffer, which re-applies stale focus states;
(c) a resident `logcat` is a heavyweight way to read a few events per minute.
`focuslog` starts its reader at "now", so nothing stale is ever replayed, and it
never writes anything into the log buffer it reads.

On a matching `entering` it looks the package up in
`/vendor/etc/power_app_cfg.xml` and calls `notifyAppState` with `state=1`; a
`leaving` of the boosted package (or an `entering` of another package) calls
`state=0`. Packages outside the 40-entry whitelist are never reported, so an
ordinary app switch costs one string compare and nothing else. With no focus
change at all, the daemon costs nothing. (The table it looks up is the effective
one: 40 stock entries plus the games added in `module/etc`.)

Notes on the event source (all verified on this GSI):

* the event is a binary payload, not a text line: `tag id | type | length |
  Focus entering <hash> <pkg>/<act> (server) | type | length | reason=...`, with
  NUL bytes in front of the text. Parsing it with `strstr`/`strchr` stops at the
  first NUL and silently matches nothing; `focuslog` uses length-bounded
  `memmem`/`memchr` over the whole payload
* only `(server)` entries are used (`(client)` ones belong to client windows),
  and `(server)` is the *end* of that string value - there is no comma after it
* the events buffer on this device is flooded by `auditd` avc lines (see
  `shark8-gsi-logspam-cosmetics`), so a live reader is required - a `-d` dump
  of the buffer usually contains nothing but audit noise

### Why the helpers are staged into /data/local/tmp

`/linkerconfig/ld.config.txt` on this GSI has (line 22) `dir.unrestricted =
/data/local/tmp` and gives *exactly that directory* the "unrestricted" linker
namespace, whose `search.paths` include `/vendor/${LIB}`. A binary started from
any other path under `/data` (including `/data/adb/modules/...`) lands in the
isolated default namespace, whose `permitted.paths` contain `/vendor/app`,
`/vendor/framework` and `/vendor/priv-app` but **not** `/vendor/${LIB}` - the
`dlopen` of `/vendor/lib64/libpowerhalwrap_vendor.so` then fails with a
misleading `library ... is not accessible for the namespace "(default)"` (no
avc denial, `md5sum` identical for the same binary from both paths).
`focuslog` only needs `liblog.so` from `/system/${LIB}` and works from anywhere,
but both binaries are staged for uniformity: `service.sh` copies `module/bin/*`
to `/data/local/tmp/bin/` at boot, `gamemode.sh` does the same on demand
(copying only when the module copy is newer) and falls back to the module path.

### Manual switch

Gamemode is off by default and never runs by itself. The switch is
`persist.shark8.gamemode.enable` (0/1); `service.sh` starts the watcher at boot
only when it is 1.

```
sh /data/adb/modules/shark8_gamemode/gamemode.sh on        # one-shot boost of the current app
sh /data/adb/modules/shark8_gamemode/gamemode.sh off       # one-shot release
sh /data/adb/modules/shark8_gamemode/gamemode.sh enable    # persist the flag + start the watcher
sh /data/adb/modules/shark8_gamemode/gamemode.sh disable   # stop the watcher + clear the flag
sh /data/adb/modules/shark8_gamemode/gamemode.sh status
```

`on`/`off` need no daemon at all: `on` does a single `dumpsys` call to find the
resumed activity and one `notifyAppState`, then exits.

### Adding a game that is not in the vendor table

The whitelist lookup in the engine is a plain string key: a package that is not
in the table it read at start-up can never be boosted, no matter what the
watcher sends (`act` must match too, see above). Adding the package to *our*
copy of the table is not enough - the engine reads its own file.

The engine accepts a second, updatable path (both strings are inside
`/vendor/lib64/libpowerhal.so`):

```
/vendor/etc/power_app_cfg.xml            stock table, part of the vendor image
/data/vendor/powerhal/power_app_cfg.xml  updatable table, preferred if present
```

`/data/vendor/powerhal/` is labeled `u:object_r:mtk_powerhal_data_file:s0`,
owned `system:system` and ships empty. Dropping a table there and restarting the
HAL (`setprop ctl.restart power-hal-1-0`) is enough - **no reboot, no vendor
overlay** (so the file-ownership rule with `shark8-gsi-logspam-cosmetics`, which
owns overlays of `/vendor` files, is untouched; this is a data path).

`scripts/install.ps1` installs `module/etc/power_app_cfg.xml` to that path
(`system:system`, 0644): the stock 40 entries plus the games added here. The
watcher resolves the same file with the same precedence, so it picks the
additions up automatically (`packages=41`).

Added entries so far (profile cloned from a stock entry of a similar game - the
project must not invent DVFS knobs of its own, cloning keeps the policy 100%
vendor):

| package                                | cloned from                | note |
|----------------------------------------|----------------------------|------|
| `com.kurogame.wutheringwaves.global`   | `com.miHoYo.GenshinImpact` | same genre (UE4 open world); marked with an XML comment in the file |

Evidence with the tags at `libPowerHal=I` / `mtkpower@impl=V`:

```
I mtkpower@impl: [notifyAppState] pc:0,  => com.kurogame.wutheringwaves.global
I libPowerHal: [PE] com.kurogame.wutheringwaves.global update cmd:206c700, param:3
I libPowerHal: [PE] com.kurogame.wutheringwaves.global update cmd:206c900, param:30
I libPowerHal: [PE] com.kurogame.wutheringwaves.global update cmd:3000000 param:0   (THERMAL_POLICY)
```

Caveat: the file is a snapshot of the stock table, so a vendor OTA that changes
`/vendor/etc/power_app_cfg.xml` is not inherited. Regenerate it by re-running
`scripts/install.ps1` after pulling the new stock file.

## API reference (verified on this device)

Signature (HIDL order, as served by the vendor impl):

```
notifyAppState(packageName, activityName, pid, state, uid)
```

Internal order in the engine differs (`state, pid, uid`) - see the wrappers in
`libpowerhalwrap_vendor.so` (`PowerHal_Wrap_notifyAppState`). `powercli` does
the reordering; call it with the HIDL order above.

* `state = 1` (also `5`) -> resumed, scan the whitelist and apply the profile.
* `state = 0` -> released, drop the profile.
* `activityName` is compared **literally** (`strcmp`). 36 of the 40 entries use
  the pseudo-activity `Common`; for those you must pass the string `Common`,
  not the real activity class. For the four entries with a real activity name
  you must pass that exact class name. Anything else silently applies nothing.

Verified by probe (`tools/probe_act.sh`, sgame = `<Activity name="Common">`):

| act passed to notifyAppState         | `[PE]` profile lines |
|--------------------------------------|----------------------|
| `Common`                             | 27                   |
| `com.foo.Bar`                        | 0                    |
| `com.tencent.tmgp.sgame.SGameActivity` | 0                  |

Other verified facts:

* the engine accepts `pid`/`uid` of an unrelated process (the profile still
  applies); they only feed the pid-based vendor nodes (fpsgo/GBE/thermal)
* the call shows up in the engine's own chain (`libPowerHal` at `I`, not `E` -
  the logspam module pins it to `E`, which hides all of these):
  `D mtkpower@impl: [notifyAppState] notifyAppState pack:..., act:..., pid:...,
  state:1, uid:...` -> `V mtkpower@impl: [powerd_req] POWER_MSG_NOTIFY_STATE:
  ...` -> `I libPowerHal: [perfNotifyAppState] pack:..., act:..., state:1,
  pid:..., uid:..., fps:-1`
* the *profile* application itself is a burst of `[PE] <pkg> update cmd:...`
  lines naming the package that was passed (for sgame + `Common`: 8 -> 36
  `[PE]` lines, all tagged `com.tencent.tmgp.sgame`). `[PE] LAUNCH ...` lines in
  between are the unrelated launch booster. Consecutive `state=1` notifications
  for the same package produce no second burst - the engine caches the current
  app state, so re-applying is a no-op
* the init service can be restarted without a reboot (drops the cached log
  levels): `setprop ctl.restart power-hal-1-0`
* engine INFO logging is off by default here (`persist.log.tag.libPowerHal=I`
  is not set; the logspam module pins it to `E`), so verification needs
  `setprop persist.log.tag.libPowerHal I` + the restart above
* `IMtkPower::mtkPowerHint(id, ms)` is NOT a scenario table: id 4 (which would
  be `EXT_LAUNCH` if ids were the 1-based `powerscntbl.xml` index) is rejected
  with `E mtkpower@impl: [mtkPowerHint] unsupport hint:4`. The valid id set is
  still unknown; `tools/probe_hints.sh` scans 1..64.

## Evidence

Applying the sgame profile (`powercli notify com.tencent.tmgp.sgame Common 2435 1 10202`)
produces the stock profile, verbatim from the vendor tables:

```
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:203c000, param:50
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:2044000, param:25
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:2044100, param:1
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:2044200, param:20
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:204c000, param:1
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:204c100, param:1
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:204c500, param:87
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:2050000, param:0
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:2060000, param:1
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:2064400, param:1
I libPowerHal: [PE] com.tencent.tmgp.sgame update cmd:3000000, param:8   (THERMAL_POLICY)
I libPowerHal: [setGPUFreq] ... set gpu opp level max: 2
```

`state=0` releases it (`netd_clear_priority_uid`, `bt a2dp low latency enter = 0`).

Boot autostart, verified over one reboot with `enable=1` and a fake whitelist
(`persist.shark8.gamemode.wl=/data/local/tmp/test-whitelist.xml`):

```
$ adb shell 'cat /data/local/tmp/gamemode.log'
09-21 16:40:36 1611 watch start pid=1611 packages=2
09-21 16:41:12 1611 release com.teslacoilsw.launcher act=Common
09-21 16:41:12 1611 apply com.teslacoilsw.launcher act=Common pid=4000 uid=10234
$ adb shell 'ps -A -o PID,NAME | grep focuslog'
 1664 focuslog
```

`log_()` writes to logcat *and* to `/data/local/tmp/gamemode.log` (rotated at
every watcher start): the same lines were missing from logcat after the earlier
boot, so the plain file is what the boot check relies on.

**Node diffing does not work as a marker on this vendor image**: the idle
values already equal the profile values (`gbe_enable1/2=1`,
`gbe_policy_mask=87`, `bhr_opp=0`, `kmin=10`, `floor_bound=3`, `floor_opp=2`,
`rescue_enhance_f=50`, `loading_th=25`, `gcc_enable=1`, `margin_mode=2`,
`top-app uclamp.min=0.00`, `policy0 min=500000`, `policy6 min=725000`). The
logs are the only reliable proof. `tools/snap.sh` dumps 36 relevant nodes
anyway (before/after).

## Vendor bugs this trigger runs into

The stock profile is applied, but parts of it cannot work on this kernel/vendor
mix - each of them logs an error per notification:

| path in the profile                    | failure                                                        |
|----------------------------------------|----------------------------------------------------------------|
| thermal `ta_fg_pid`                    | `E libPowerHal: Could not open '/proc/driver/thermal/ta_fg_pid'` (no `/proc/driver/thermal` in this kernel; the kernel uses the generic Linux thermal framework, 35 zones) - **silenced in cosmetics v5.1** |
| GED `gx_top_app_pid`                   | `E libPowerHal: Could not open '/sys/module/ged/parameters/gx_top_app_pid'` (`/sys/module/ged` is loaded but this GED generation has no pid parameter) - **silenced in cosmetics v5.1** |
| `PERF_RES_NET_NETD_BOOST_UID` etc.     | `E [NetdAgentCmd] dispatchNetdagentCmd failed` + `SetPriorityWithUID fail` (netdagent's socket is commented out in `/vendor/etc/init/netdagent.rc`, no avc denial); only fires for profiles that carry the net-boost resources (sgame-style), not for the cloned Genshin profile - **silenced in cosmetics v5.2/v5.3** (all 8 netdagent log calls nop'ed out of `libpowerhal.so`, plus the daemon's own `E NetdagentIptables/NetdagentService` lines nop'ed out of `/vendor/bin/netdagent` - that one is a real iptables failure, the patch only hides it) |

Both missing nodes are write-only "tell the driver which app is in front" hints.
Neither can be created from userspace, so the per-app thermal/GED policy is dead
on this kernel regardless; `shark8-gsi-logspam-cosmetics` v5.1 repoints both
`.rodata` path literals in `/vendor/lib64/libpowerhal.so` at `/dev/null`, which
makes the write a successful no-op (the engine then also stops retrying it).

Noise budget per notification with the logspam module's tags (`libPowerHal=E`):
before v5.1 `state=1` was ~6 `E libPowerHal` lines + 3 `I libPowerHal-bt` lines,
`state=0` ~2 `E` + 1 `I libPowerHal-bt`; after v5.1 the two node paths are gone
(verified: 0 `E libPowerHal` with the tag lifted to `V`); after v5.2 the net-boost
dispatch is gone as well and `persist.log.tag.libPowerHal-bt=E` mutes the BT
tag, so a net-boost profile is down to 0 `libPowerHal` lines too (verified).

Silencing anything else in that library is a binary patch of `libpowerhal.so`,
and that file is owned by `shark8-gsi-logspam-cosmetics` (which already patches
it). Further silencing belongs there, not here.

## Layout

```
module/                 KernelSU module (id shark8_gamemode)
  module.prop
  service.sh            stages the helpers, starts the watcher if the flag is 1
  gamemode.sh           watcher + on/off/enable/disable/status
  bin/powercli          aarch64 binary (built from tools/powercli.c)
  bin/focuslog          aarch64 binary (built from tools/focuslog.c)
  etc/power_app_cfg.xml stock table + added games -> /data/vendor/powerhal/
tools/                  diagnostics / prototypes, not shipped
  powercli.c            the HIDL client (dlopen libpowerhalwrap_vendor.so)
  focuslog.c            liblog events reader -> entering/leaving lines (-v, -x)
  probe_focuslog.sh     focuslog vs logcat on the same focus changes
  probe_notify.sh       tags -> HAL restart -> notify -> log dump
  probe_act.sh          does the activity string matter?
  probe_hints.sh        scan IMtkPower::mtkPowerHint ids 1..64
  probe_events.sh       are the am_* activity events present? (no)
  probe_events2.sh      which events does the buffer really carry? (input_focus)
  probe_delivery.sh     logcat -> FIFO delivery + field parse check
  test-gamemode.sh      end-to-end test against the installed module
  test-whitelist.xml    fake whitelist (launcher + Settings)
  snap.sh               dump the relevant sysfs/cpuctl nodes before/after
scripts/
  build.ps1             NDK build of module/bin/{powercli,focuslog}
  install.ps1           push the module to /data/adb/modules + the app table
```

## Build

```
powershell -File scripts/build.ps1
```

NDK r27d, `--target=aarch64-linux-android21 -fPIE -pie -O2`, links only
`-ldl`.

## Install

```
powershell -File scripts/install.ps1
```

The module lands in `/data/adb/modules/shark8_gamemode` and does nothing until
the flag is set (`service.sh` only runs at boot, so `enable` survives reboots
via the persistent property). The helpers are staged into `/data/local/tmp/bin/`
at every boot. KernelSU needs no sepolicy additions: the daemon runs as root and
only uses binder + a read-only logd socket.

## Verify

```
M=/data/adb/modules/shark8_gamemode
adb shell "sh $M/gamemode.sh status"
adb shell "sh $M/gamemode.sh enable"           # or: on, for a single shot
adb shell 'tail -5 /data/local/tmp/gamemode.log'
# expect: watch start pid=.. packages=40 / apply <pkg> act=Common pid=.. uid=..
adb shell 'ps -A -o PID,NAME | grep focuslog'  # the reader must be alive
adb shell 'setprop persist.log.tag.libPowerHal I; setprop ctl.restart power-hal-1-0'
# launch a whitelisted game, then:
adb shell 'logcat -d | grep "PE. com.tencent.tmgp.sgame" | tail'
adb shell "sh $M/gamemode.sh disable"          # restore the tags afterwards
```

## Uninstall

```
adb shell 'sh /data/adb/modules/shark8_gamemode/gamemode.sh disable'
adb shell 'rm -rf /data/adb/modules/shark8_gamemode'
```

then reboot. Nothing outside that directory and `/data/local/tmp` is touched:
the daemon writes `bin/{powercli,focuslog}` (staging), `gamemode-whitelist.map`,
`gamemode.state`, `gamemode.pid`, `gamemode.fifo`, `gamemode.log`,
`gamemode.log.err`, and (only via `enable`) the persistent flags
`persist.shark8.gamemode.enable` / `persist.shark8.gamemode.wl`.

The installed table is the one exception, and it is what makes added games work:

```
adb shell 'rm /data/vendor/powerhal/power_app_cfg.xml'   # back to the stock table
adb shell 'setprop ctl.restart power-hal-1-0'
```

## Open questions

* `mtkPowerHint` id table (1..64 scan pending) - could give cheap one-shot
  boosts (`EXT_LAUNCH` on game start) without a whitelist entry.
* Do we want the three failing profile paths silenced? Done: all three are
  silenced in the logspam project (v5.1 for the two kernel nodes, v5.2 for the
  netdagent dispatch, and the daemon itself in v5.3).
* Per-app `fps` field in `power_app_cfg.xml`: the engine logs `fps:-1`; the
  stock framework may have passed the display refresh rate. Untested.
