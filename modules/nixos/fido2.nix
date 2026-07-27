{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.omarchy;

  # Upstream gates pam_fprintd behind the lid state so a shut clamshell (where
  # the reader is unreachable) drops straight to the password prompt instead of
  # blocking until the reader times out. pam_exec needs a literal absolute path,
  # so point it at the store copy rather than $OMARCHY_PATH/bin.
  lidClosed = pkgs.writeShellScript "omarchy-hw-laptop-closed" (builtins.readFile ../../bin/omarchy-hw-laptop-closed);

  # Insert the gate immediately before fprintd so success=1 skips exactly it.
  clamshellGate = service: {
    rules.auth.omarchy-clamshell-gate = {
      enable = cfg.fido2_auth.fingerprint_support;
      order = config.security.pam.services.${service}.rules.auth.fprintd.order - 1;
      control = "[success=1 default=ignore]";
      modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
      args = ["quiet" "${lidClosed}"];
    };
  };
in {
  config = lib.mkIf (cfg ? fido2_auth && cfg.fido2_auth.enable) {
    # Enable FIDO2/WebAuthn support
    security.pam.u2f = {
      enable = true;
      # Allow fallback to password if FIDO2 fails
      cue = true;
      # Interactive mode for user prompts
      interactive = true;
    };

    # Required packages for FIDO2 support
    environment.systemPackages = with pkgs; [
      libfido2
      pamu2fcfg # Tool for mapping FIDO2 devices
      yubikey-manager
      yubikey-personalization
    ];

    # udev rules for FIDO2 devices
    services.udev.packages = with pkgs; [
      yubikey-personalization
      libfido2
    ];

    # Enable smart card services (needed for some FIDO2 devices)
    services.pcscd.enable = true;

    # Add fingerprint support if enabled
    services.fprintd = lib.mkIf (cfg.fido2_auth.fingerprint_support) {
      enable = true;
    };

    # Configure PAM for FIDO2 and fingerprint authentication
    security.pam.services = {
      sudo = lib.mkMerge [
        # Try FIDO2 first, then fall back to password. Must go through u2fAuth
        # rather than a `text` override: setting `text` replaces the whole
        # generated stack, which drops the account/session/password lines (and
        # any fprintd rules below) and leaves sudo unusable.
        (lib.mkIf (cfg.fido2_auth.sudo_auth) {
          u2fAuth = true;
        })
        (lib.mkIf (cfg.fido2_auth.fingerprint_support) {
          fprintAuth = true;
        })
        (clamshellGate "sudo")
      ];
      login = lib.mkIf (cfg.fido2_auth.fingerprint_support) {
        fprintAuth = true;
      };
      # Fingerprint for polkit prompts, gated by lid state like sudo.
      polkit-1 = lib.mkMerge [
        (lib.mkIf (cfg.fido2_auth.fingerprint_support) {
          fprintAuth = true;
        })
        (clamshellGate "polkit-1")
      ];
      # Omarchy 4 shell lock authenticates against the omarchy-lock-fingerprint
      # PAM service (shell/plugins/lock PamContext config:"omarchy-lock-fingerprint").
      omarchy-lock-fingerprint = lib.mkIf (cfg.fido2_auth.fingerprint_support) {
        fprintAuth = true;
      };
    };
  };
}
