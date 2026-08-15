{
  lib,
  stdenv,
  fetchFromGitHub,
  qt6,
  makeDesktopItem,
  copyDesktopItems,
}:
# quattro replaced gnome-calculator with omacalc, which follows the Omarchy
# theme and system light/dark mode. Bound to SUPER + CTRL + Q and XF86Calculator
# in default/hypr/bindings/utilities.lua.
stdenv.mkDerivation rec {
  pname = "omacalc";
  version = "0.2.2";

  src = fetchFromGitHub {
    owner = "omacom-io";
    repo = "omacalc";
    tag = "v${version}";
    hash = "sha256-I+WxkMz/2hCf4OpJKu99+30c0CxyxFD0M6eSLFDLs1I=";
  };

  nativeBuildInputs = [qt6.qmake qt6.wrapQtAppsHook copyDesktopItems];
  buildInputs = [qt6.qtbase qt6.qtdeclarative];

  # Upstream ships no install target: qmake's default would land the binary in
  # the source dir. Install it (and the bundled iA Writer fonts) by hand.
  installPhase = ''
    runHook preInstall
    install -Dm755 omacalc $out/bin/omacalc
    install -Dm644 -t $out/share/fonts/truetype/omacalc $src/fonts/*.ttf
    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "omacalc";
      desktopName = "Calculator";
      exec = "omacalc";
      icon = "accessories-calculator";
      categories = ["Utility" "Calculator"];
      startupWMClass = "omacalc";
    })
  ];

  meta = with lib; {
    description = "Omarchy's simple calculator";
    homepage = "https://github.com/omacom-io/omacalc";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "omacalc";
    platforms = platforms.linux;
  };
}
