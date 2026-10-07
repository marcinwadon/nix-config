{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
# Ghosthub is not in nixpkgs and ships only as a signed, notarized DMG
# (https://ghosthub.ai/guide/ — Homebrew tap or a manual download). This
# repackages that release artifact; the hash is the one the upstream cask
# publishes, so we're demonstrably fetching the same bytes Homebrew would.
#
# Version bumps are manual: change `version`, then refresh `hash` from the
# release's SHA256SUMS via
#   nix hash convert --to sri --hash-algo sha256 <sha256-from-SHA256SUMS>
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ghosthub";
  version = "0.6.0";

  src = fetchurl {
    url = "https://github.com/kenn-io/ghosthub/releases/download/v${finalAttrs.version}/Ghosthub_${finalAttrs.version}_macos_arm64.dmg";
    hash = "sha256-EwbgrYdc9i4zTx/6/NBMtnlBk8bYPLeFZ1FNuxdUlJw=";
  };

  # The DMG is UDZO-compressed but carries an APFS volume, which `undmg`
  # cannot read. 7-Zip can, and it preserves the framework symlinks that the
  # code signature covers.
  nativeBuildInputs = [_7zz];

  unpackPhase = ''
    runHook preUnpack
    7zz x -snld "$src"
    runHook postUnpack
  '';

  sourceRoot = ".";

  # The bundle is signed + notarized (Developer ID: William McKinney).
  # fixupPhase would strip/rewrite the Mach-O binaries and invalidate that,
  # which Gatekeeper turns into a silent launch failure — copy it untouched.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R Ghosthub.app "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "libghostty-based native macOS terminal for local and remote tmux fleets";
    homepage = "https://ghosthub.ai/";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    platforms = ["aarch64-darwin"];
  };
})
