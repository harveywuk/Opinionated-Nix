inputs: {
  config,
  pkgs,
  lib,
  ...
}: let
  themes = import ../themes.nix;
  themeNames = builtins.attrNames themes;

  # Map theme names to their actual directory (some themes share directories)
  themeSourceMap = {
    "rose-pine-dawn" = "rose-pine";
    "rose-pine-moon" = "rose-pine";
    "gruvbox-light" = "gruvbox";
  };

  # Get the source directory for a theme
  getThemeSource = themeName:
    if builtins.hasAttr themeName themeSourceMap
    then themeSourceMap.${themeName}
    else themeName;

  # Theme dir = the checked-in configs, rendered offline from each theme's
  # upstream colors.toml with `omarchy-theme-set-templates` (see OMARCHY4-PORT.md).
  # That covers foot.ini too, which quattro now generates from the same source.
  themeDir = themeName:
    pkgs.runCommand "omarchy-theme-${themeName}" {} ''
      cp -r ${../../config/themes/${getThemeSource themeName}} $out
      chmod -R u+w $out
    '';
in {
  # Install each theme directory individually
  home.file = lib.listToAttrs (map (themeName: {
      name = ".config/omarchy/themes/${themeName}";
      value = {
        source = themeDir themeName;
        recursive = true;
      };
    })
    themeNames);

  # Create initial symlink to current theme
  home.activation.omarchy-theme-symlink = lib.hm.dag.entryAfter ["writeBoundary"] ''
    STATE="$HOME/.local/state/omarchy/current"
    THEME_LINK="$STATE/theme"

    mkdir -p "$STATE"

    # The runtime selection wins over the build-time default, so a rebuild
    # doesn't silently revert a theme picked with omarchy-theme-set.
    THEME="${config.omarchy.theme}"
    if [ -r "$STATE/theme.name" ]; then
      THEME="$(cat "$STATE/theme.name")"
    fi
    if [ ! -d "$HOME/.config/omarchy/themes/$THEME" ]; then
      THEME="${config.omarchy.theme}"
    fi

    if [ -e "$THEME_LINK" ] && [ ! -L "$THEME_LINK" ]; then
      # omarchy-theme-set turned current/theme into a directory of symlinks into
      # the generation current at the time. Re-apply after a switch so they track
      # the new generation and the shell hot-reloads. Best-effort (no session
      # pre-login).
      $DRY_RUN_CMD env \
        OMARCHY_PATH="$HOME/.local/share/omarchy" \
        PATH="$HOME/.local/share/omarchy/bin:$PATH" \
        omarchy-theme-set "$THEME" >/dev/null 2>&1 || true
    else
      # Fresh install: plain symlink tracks the generation on its own.
      $DRY_RUN_CMD ln -sfn "$HOME/.config/omarchy/themes/$THEME" "$THEME_LINK"
    fi
  '';
}
