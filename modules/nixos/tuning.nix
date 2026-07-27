{
  config,
  lib,
  ...
}: {
  # Memory / swap tuning ported from quattro's etc/ drop-ins:
  #   default/systemd/zram-generator.conf.d/90-omarchy.conf
  #   etc/tmpfiles.d/omarchy-zswap.conf
  #   etc/sysctl.d/99-omarchy-sysctl.conf
  #   etc/systemd/logind.conf.d/20-inhibit-delay.conf
  #   etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf

  # Compressed swap in RAM. zstd averages around 3:1, so even a full device
  # occupies roughly a third of RAM. Priority sits above the disk swapfile.
  zramSwap = {
    enable = lib.mkDefault true;
    algorithm = lib.mkDefault "zstd";
    memoryPercent = lib.mkDefault 100;
    priority = lib.mkDefault 100;
  };

  # zswap in front of swap-on-zram just double-compresses pages and breaks
  # zramctl accounting. Boot-only, so flipping it on by hand for an experiment
  # sticks until reboot.
  boot.kernelParams = ["zswap.enabled=0"];

  boot.kernel.sysctl = {
    # Solve common flakiness with SSH (MTU discovery on flaky links).
    "net.ipv4.tcp_mtu_probing" = lib.mkDefault 1;

    # Tune reclaim for swap on zram, which is orders of magnitude faster than
    # the disk swapfile these defaults assume.
    "vm.swappiness" = lib.mkDefault 150;
    "vm.vfs_cache_pressure" = lib.mkDefault 50;
    "vm.page-cluster" = lib.mkDefault 0;
    "vm.watermark_boost_factor" = lib.mkDefault 0;
    "vm.watermark_scale_factor" = lib.mkDefault 125;
    "vm.dirty_background_bytes" = lib.mkDefault 67108864;
    "vm.dirty_bytes" = lib.mkDefault 268435456;
    "vm.dirty_writeback_centisecs" = lib.mkDefault 1500;
  };

  # omarchy-system-sleep-lock holds a delay inhibitor so the session locks
  # before suspend. Five seconds is not enough when closing the lid also
  # reconfigures displays, because Quickshell waits for the screen set to settle.
  # Written as the upstream drop-in rather than services.logind.settings, which
  # only exists on recent nixpkgs.
  environment.etc."systemd/logind.conf.d/20-inhibit-delay.conf".text = ''
    [Login]
    InhibitDelayMaxSec=15
  '';

  # Keep Wi-Fi power save off: it trades 20-300ms latency spikes on idle links
  # for a fraction of a watt, and broken firmware (Intel BE200/BE211) drops the
  # link outright when it naps.
  networking.networkmanager.settings.connection = {
    "wifi.powersave" = 2;
  };
}
