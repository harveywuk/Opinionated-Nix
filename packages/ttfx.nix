{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
# quattro replaced python-terminaltexteffects with ttfx, a parity-exact Rust
# port that renders byte-identical frames from a single dependency-free binary.
# The screensaver runs at --frame-rate 120, which the Python original could not
# hold on a fullscreen canvas.
rustPlatform.buildRustPackage rec {
  pname = "ttfx";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "omacom-io";
    repo = "ttfx";
    tag = "v${version}";
    hash = "sha256-uJOM/mIhM/0pAu2Aa1q6XSaKcM7BxH7mxoU5eUVG9Ek=";
  };

  cargoHash = "sha256-pVS/GPipxRr45lE8Jnp86Jkg2EdAuoxg1pFx+UMzgXc=";

  meta = with lib; {
    description = "Terminal text effects as a single static binary";
    homepage = "https://github.com/omacom-io/ttfx";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "ttfx";
  };
}
