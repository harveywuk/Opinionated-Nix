{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.omarchy;
  voxtype = pkgs.callPackage ../../packages/voxtype.nix {};
in {
  config = lib.mkIf cfg.voxtype.enable {
    # Deploy the voxtype config only if the user doesn't have one yet, so
    # runtime edits survive a rebuild. omarchy.voxtype.config_file overrides the
    # Omarchy default with a personal one (model, initial_prompt, replacements).
    home.activation.voxtype-config = lib.hm.dag.entryAfter ["writeBoundary"] ''
      VOXTYPE_CONFIG="$HOME/.config/voxtype/config.toml"
      if [[ ! -f "$VOXTYPE_CONFIG" ]]; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$VOXTYPE_CONFIG")"
        $DRY_RUN_CMD cp "${
        if cfg.voxtype.config_file != null
        then cfg.voxtype.config_file
        else ../../default/voxtype/config.toml
      }" "$VOXTYPE_CONFIG"
      fi
    '';

    # Enable GPU in voxtype if Vulkan is available
    home.activation.voxtype-gpu = lib.hm.dag.entryAfter ["writeBoundary" "voxtype-config"] ''
      if command -v vulkaninfo &>/dev/null && vulkaninfo --summary &>/dev/null 2>&1; then
        $DRY_RUN_CMD ${voxtype}/bin/voxtype setup gpu --enable 2>/dev/null || true
      fi
    '';

    # Systemd user service for voxtype daemon
    systemd.user.services.voxtype = {
      Unit = {
        Description = "Voxtype voice dictation daemon";
        After = ["graphical-session.target"];
      };

      Service = {
        Type = "simple";
        # Use Vulkan binary for GPU acceleration (better compatibility with RDNA 3.5+)
        ExecStart = "${voxtype}/lib/voxtype/voxtype-vulkan daemon";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}
