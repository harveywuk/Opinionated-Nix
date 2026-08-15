{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.omarchy;
in {
  programs.kitty = {
    enable = lib.mkDefault true;

    font = {
      name = lib.mkDefault "JetBrainsMono Nerd Font";
      size = lib.mkDefault 9;
    };

    # Mirrors upstream config/kitty/kitty.conf. Every value is wrapped in
    # mkDefault individually: programs.kitty.settings is an attrsOf, so a
    # mkDefault around the whole attrset gets dropped wholesale as soon as a
    # user defines any kitty setting of their own — taking the theme include
    # with it, which leaves kitty unthemed.
    settings = {
      # Load theme from runtime config (allows dynamic theme switching)
      include = lib.mkDefault "~/.local/state/omarchy/current/theme/kitty.conf";

      bold_italic_font = lib.mkDefault "auto";

      # Window
      window_padding_width = lib.mkDefault 14;
      hide_window_decorations = lib.mkDefault "yes";
      confirm_os_window_close = lib.mkDefault 0;

      # Allow remote access
      allow_remote_control = lib.mkDefault "yes";

      # Aesthetics
      cursor_shape = lib.mkDefault "block";
      cursor_blink_interval = lib.mkDefault 0;
      enable_audio_bell = lib.mkDefault "no";

      # Minimal tab bar styling
      tab_bar_edge = lib.mkDefault "bottom";
      tab_bar_style = lib.mkDefault "powerline";
      tab_powerline_style = lib.mkDefault "slanted";
      tab_title_template = lib.mkDefault "{title}{' :{}:'.format(num_windows) if num_windows > 1 else ''}";
    };

    keybindings = {
      # Universal copy/paste (works with Hyprland's Super+C/V → Ctrl/Shift+Insert mapping)
      "ctrl+insert" = lib.mkDefault "copy_to_clipboard";
      "shift+insert" = lib.mkDefault "paste_from_clipboard";
    };
  };
}
