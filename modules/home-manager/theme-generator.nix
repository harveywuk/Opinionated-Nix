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
    THEME_SYMLINK="$HOME/.local/state/omarchy/current/theme"
    CURRENT_THEME="${config.omarchy.theme}"

    mkdir -p "$(dirname "$THEME_SYMLINK")"

    # Only create symlink if it doesn't exist (don't override user's selection)
    if [[ ! -L "$THEME_SYMLINK" ]]; then
      $DRY_RUN_CMD ln -sf "$HOME/.config/omarchy/themes/$CURRENT_THEME" "$THEME_SYMLINK"
    fi
  '';
}
