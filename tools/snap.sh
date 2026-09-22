#!/system/bin/sh
# powercli experiment harness: print the value of every readback node that the
# MTK whitelist/scenario tables (power_app_cfg.xml, powerscntbl.xml) can touch.
nodes="/sys/module/mtk_fpsgo/parameters/bhr_opp
/sys/module/mtk_fpsgo/parameters/bhr
/sys/module/mtk_fpsgo/parameters/kmin
/sys/module/mtk_fpsgo/parameters/floor_bound
/sys/module/mtk_fpsgo/parameters/floor_opp
/sys/module/mtk_fpsgo/parameters/rescue_enhance_f
/sys/module/mtk_fpsgo/parameters/loading_th
/sys/module/mtk_fpsgo/parameters/gcc_enable
/sys/module/mtk_fpsgo/parameters/gcc_fps_margin
/sys/kernel/fpsgo/fbt/boost_ta
/sys/kernel/fpsgo/fbt/limit_cfreq
/sys/kernel/fpsgo/fbt/limit_rfreq
/sys/kernel/fpsgo/fstb/margin_mode
/sys/kernel/fpsgo/fstb/fstb_soft_level
/sys/kernel/fpsgo/fstb/set_cam_active
/sys/kernel/fpsgo/xgf/xgf_spid_list
/sys/kernel/gbe/gbe_enable1
/sys/kernel/gbe/gbe_enable2
/sys/kernel/gbe/gbe_policy_mask
/sys/kernel/gbe/gbe2_fg_pid
/sys/kernel/gbe/gbe2_loading_th
/sys/module/ged/parameters/g_fb_dvfs_threshold
/sys/module/ged/parameters/boost_gpu_enable
/sys/module/ged/parameters/enable_gpu_boost
/sys/kernel/ged/hal/custom_upbound_gpu_freq
/dev/cpuctl/top-app/cpu.uclamp.min
/dev/cpuctl/foreground/cpu.uclamp.min
/dev/cpuctl/top-app/cpu.uclamp.latency_sensitive
/sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq
/sys/devices/system/cpu/cpufreq/policy6/scaling_min_freq
/sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq
/sys/devices/system/cpu/cpufreq/policy0/sugov_ext/up_rate_limit_us
/sys/devices/system/cpu/cpufreq/policy0/sugov_ext/down_rate_limit_us
/sys/devices/system/cpu/cpufreq/policy6/sugov_ext/up_rate_limit_us
/sys/devices/system/cpu/cpufreq/policy6/sugov_ext/down_rate_limit_us"

for f in $nodes; do
  v=$(cat "$f" 2>/dev/null)
  echo "$f = ${v:-<none>}"
done
