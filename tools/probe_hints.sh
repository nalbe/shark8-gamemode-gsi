#!/system/bin/sh
# Probe which MTKPOWER_HINT ids reach libpowerhal: read marker nodes right after
# each hint. Baselines on this device (idle): bhr_opp=0, top-app uclamp.min=0,
# policy0 scaling_min_freq=500000, policy6 scaling_min_freq=725000.
i=1
while [ $i -le 34 ]; do
  /data/local/tmp/powercli hint $i 400 >/dev/null 2>&1
  b=$(cat /sys/module/mtk_fpsgo/parameters/bhr_opp)
  u=$(cat /dev/cpuctl/top-app/cpu.uclamp.min)
  f0=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq)
  f6=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq)
  echo "id=$i bhr=$b uclamp=$u p0=$f0 p6=$f6"
  i=$((i+1))
done
