inputs: {
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.omarchy;
  packages = import ../packages.nix {inherit pkgs config lib;};
in {
  # Create /bin/bash symlink for Omarchy script compatibility
  systemd.tmpfiles.rules = [
    "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
  ];

  security.rtkit.enable = true;

  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Seamless boot and login experience
  boot = lib.mkIf cfg.seamless_boot.enable {
    # Plymouth boot splash
    plymouth = {
      enable = true;
      theme = cfg.seamless_boot.plymouth_theme;
      themePackages = packages.plymouthThemes;
    };

    # Silent boot configuration
    consoleLogLevel = lib.mkIf cfg.seamless_boot.silent_boot 3;
    initrd.verbose = lib.mkIf cfg.seamless_boot.silent_boot false;
    kernelParams = lib.mkIf cfg.seamless_boot.silent_boot [
      "quiet"
      "splash"
      "loglevel=3"
      "systemd.show_status=auto"
      "udev.log_priority=3"
      "rd.udev.log_level=3"
      "boot.shell_on_fail"
    ];
  };

  # UWSM integration for Hyprland (always on; SDDM relies on hyprland-uwsm.desktop)
  programs.uwsm.enable = true;

  # Login configuration (matches upstream omarchy: SDDM Wayland greeter on Hyprland).
  # Autologin path mirrors /etc/sddm.conf.d/autologin.conf from upstream install/login/sddm.sh.
  services.displayManager = let
    # The greeter runs its own minimal Hyprland compositor, which does NOT
    # inherit the system keyboard layout the way the user session does. Without
    # an explicit input block it defaults to us/qwerty, locking out anyone on a
    # different layout (e.g. dvorak/azerty) — they type the right password but
    # the wrong keysyms reach PAM. Source it from services.xserver.xkb so the
    # greeter matches the system's keyboard. (Upstream's static greeter config
    # omits this; on Arch the greeter inherits XKB defaults differently.)
    xkb = config.services.xserver.xkb;
    sddmHyprlandConf =
      pkgs.writeText "sddm-hyprland.conf"
      (builtins.readFile ../../default/sddm/hyprland.conf
        + ''

          input {
            kb_layout = ${xkb.layout}
            kb_variant = ${xkb.variant}
            kb_options = ${xkb.options}
          }
        '');
    hyprlandPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    loginUser =
      if cfg.seamless_boot.username != null
      then cfg.seamless_boot.username
      else cfg.username;
  in {
    sddm = {
      enable = true;
      wayland.enable = true;
      package = pkgs.kdePackages.sddm;
      theme = "omarchy";
      extraPackages = packages.sddmThemes;
      autoNumlock = false;
      settings = {
        Theme.CursorTheme = lib.mkDefault "";
        # Wayland greeter runs on a minimal Hyprland compositor
        Wayland.CompositorCommand = "${hyprlandPkg}/bin/Hyprland --config ${sddmHyprlandConf}";
        # Match upstream: Wayland-only, no X11 fallback (omarchy commit 4eb3a919)
        General.DisplayServer = "wayland";
      };
    };
    defaultSession = "hyprland-uwsm";
    autoLogin = lib.mkIf cfg.seamless_boot.enable {
      enable = true;
      user = loginUser;
    };
  };

  # Upstream installs /etc/pam.d/sddm and then strips the gnome-keyring auth/password
  # lines to avoid creating an encrypted login keyring that conflicts with
  # passwordless Default_keyring auto-unlock. NixOS exposes that knob directly.
  security.pam.services.sddm.enableGnomeKeyring = false;
  security.pam.services.sddm-autologin.enableGnomeKeyring = false;

  # Omarchy 4 shell lock screen authenticates against this PAM service
  # (shell/plugins/lock PamContext config:"omarchy-lock-password"). The default
  # NixOS PAM stack provides the unix password auth it needs; the fingerprint
  # counterpart (omarchy-lock-fingerprint) is added in fido2.nix when enabled.
  security.pam.services.omarchy-lock-password = {};

  # Install packages
  environment.systemPackages = packages.systemPackages;
  programs.direnv.enable = true;

  # nix-ld for running unpatched binaries (e.g., Python venvs with native deps)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [stdenv.cc.cc];

  environment.sessionVariables = {
    OMARCHY_PATH = "$HOME/.local/share/omarchy";
  };

  # Upstream ships bin/ in /usr/bin; here it's under $HOME and home.sessionPath
  # only reaches interactive shells. Add it in /etc/profile so `bash -l`
  # (omarchy-shell menu actions, SSH) finds omarchy-* too.
  environment.extraInit = ''
    case ":$PATH:" in
      *":$HOME/.local/share/omarchy/bin:"*) ;;
      *) export PATH="$HOME/.local/share/omarchy/bin:$PATH" ;;
    esac
  '';

  # Raise soft fd limit (omarchy install/config/increase-fd-limit.sh equivalent)
  systemd.settings.Manager.DefaultLimitNOFILESoft = 65536;

  # Network service discovery and file manager network browsing
  # (Arch provides these implicitly with most desktop setups)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    browseDomains = ["local"];
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
  services.gvfs.enable = true;

  # Printing support (CUPS stack - matches Omarchy's cups/cups-browsed/cups-filters/cups-pdf)
  services.printing = {
    enable = true;
    browsing = true;
  };

  # Power management profiles (performance/balanced/power-saver)
  services.power-profiles-daemon.enable = true;

  # Credential storage for apps (gnome-keyring); SDDM PAM lines configured above.
  services.gnome.gnome-keyring.enable = true;

  # Notice dropped SSH connections within a minute instead of hanging until TCP
  # gives up, so the shell's ssh wrapper can clean up and reconnect. ~/.ssh/config
  # is read first and wins, so per-host overrides still apply.
  # Mirrors install/config/ssh-keepalive.sh.
  programs.ssh.extraConfig = ''
    Host *
      ServerAliveInterval 15
      ServerAliveCountMax 3
      ConnectTimeout 10
  '';

  # Networking
  services.resolved.enable = true;
  hardware.bluetooth.enable = true;

  # NetworkManager owns Wi-Fi, on its default wpa_supplicant backend. Upstream
  # left iwd in b19dc7ea (May 2026) and retires the iwd + impala pair together in
  # omarchy-upgrade-to-quattro; we had switched to iwd for the impala TUI back
  # when Omarchy still used it. The shell's own network panel replaced that TUI,
  # and the quattro network scripts (omarchy-network-{password,qr,band}) read the
  # passphrase out of NetworkManager, which only holds it on this backend.
  networking = {
    networkmanager.enable = true;
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-color-emoji
    nerd-fonts.caskaydia-mono
    nerd-fonts.jetbrains-mono
  ];
}
