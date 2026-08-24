{
  config,
  pkgs,
  lib,
  ...
}: let
  # Upstream skel, kept at upstream's path (config/hypr/hyprsunset.conf) so
  # omarchy-refresh-hyprsunset can restore it through omarchy-refresh-config
  # like every other refreshable config. Seeded once as a user-owned file:
  # Setup > Config > Hyprsunset edits it and omarchy-restart-hyprsunset applies
  # it, so it must not be a read-only store symlink.
  hyprsunsetConf = builtins.readFile ../../config/hypr/hyprsunset.conf;
in {
  # Hyprsunset - Blue light filter with manual toggle support
  # Default configuration disables automatic tinting
  # Use omarchy-toggle-nightlight to toggle nightlight mode

  home.activation.seedHyprsunsetConf = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -e "$HOME/.config/hypr/hyprsunset.conf" ]; then
      mkdir -p "$HOME/.config/hypr"
      cp ${pkgs.writeText "hyprsunset.conf" hyprsunsetConf} "$HOME/.config/hypr/hyprsunset.conf"
      chmod 644 "$HOME/.config/hypr/hyprsunset.conf"
    fi
  '';

  # Systemd user service for hyprsunset
  systemd.user.services.hyprsunset = {
    Unit = {
      Description = "Hyprsunset - Blue light filter for Hyprland";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };

    Service = {
      ExecStart = "${pkgs.hyprsunset}/bin/hyprsunset";
      Restart = "on-failure";
      RestartSec = 3;
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}
