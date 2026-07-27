{pkgs, ...}: {
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      serif = ["Noto Serif"];
      sansSerif = ["Noto Sans"];
      monospace = ["Caskaydia Mono Nerd Font"];
    };
  };

  # Arabic script selection, ported from quattro's
  # default/fontconfig/conf.avail/50-omarchy.conf: prefer Naskh (standard
  # Arabic) over Nastaliq (Urdu style), keep Urdu on Nastaliq, and name Naskh as
  # a last-resort family so Chromium/Electron — which resolve missing glyphs one
  # character at a time, without lang on the pattern — don't fall through to a
  # raw charset scan that lands on Nastaliq or Kufi.
  xdg.configFile."fontconfig/conf.d/50-omarchy-arabic.conf".text = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <match target="pattern">
        <test name="lang" compare="contains">
          <string>ar</string>
        </test>
        <edit name="family" mode="prepend" binding="strong">
          <string>Noto Naskh Arabic</string>
        </edit>
      </match>

      <match target="pattern">
        <test name="lang" compare="contains">
          <string>ur</string>
        </test>
        <edit name="family" mode="append" binding="strong">
          <string>Noto Nastaliq Urdu</string>
        </edit>
      </match>

      <match target="pattern">
        <edit name="family" mode="append" binding="strong">
          <string>Noto Naskh Arabic</string>
        </edit>
      </match>
    </fontconfig>
  '';

  # Don't autostart the print-queue applet (quattro config/autostart).
  xdg.configFile."autostart/print-applet.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';

  # Install omarchy icon font as a nix package
  home.packages = [
    (pkgs.stdenvNoCC.mkDerivation {
      name = "omarchy-font";
      src = ../../config;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype
        cp $src/omarchy.ttf $out/share/fonts/truetype/omarchy.ttf
      '';
    })
  ];
}
