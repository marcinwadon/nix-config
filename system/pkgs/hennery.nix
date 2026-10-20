{
  lib,
  stdenvNoCC,
  fetchurl,
}:
# hennery (https://github.com/marcinwadon/hennery): the agent-session collector
# + per-machine host. Repackages the signed release archives as-is; it is NOT
# built from source here.
#
# A bump is one edit, all in this file: `version` and the three `sha256`s below.
# Take the hashes from the release's SHA256SUMS, and only after running the
# README's "Verify a release installer before running it" block adapted to the
# archives (signed tag from fingerprint F26C7F594DFE84D131703AFC23E5A318AE8D2861,
# then `gh attestation verify` of SHA256SUMS and of each archive). The hex is
# kept exactly as SHA256SUMS prints it so the two can be compared by eye.
#
# v0.1.4: tag object signed by the pinned fingerprint, source commit
# 0f3d25171f9cf1805c1d4a1752cdbe20bf69007b; SHA256SUMS and all three archives
# carry a Sigstore provenance attestation for release.yml@refs/tags/v0.1.4.
let
  version = "0.1.4";

  archives = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      sha256 = "a6b567c2aea8ac6ecb7d8803847a3171a3d687fb66d1cf722eb3a905b4a4ea79";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      sha256 = "a8f0910df414edc447d03c6c4c1cdb3784d0fa10bac0c881dee51c4e3a4a742d";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      sha256 = "83d6fe147c20eace44d53cf58d40b1a36d5477f769380198f13274a19d61a16d";
    };
  };

  system = stdenvNoCC.hostPlatform.system;
  archive = archives.${system} or (throw "hennery: no release archive for ${system}");
in
  stdenvNoCC.mkDerivation {
    pname = "hennery";
    inherit version;

    src = fetchurl {
      url = "https://github.com/marcinwadon/hennery/releases/download/v${version}/hennery-${archive.target}.tar.xz";
      inherit (archive) sha256;
    };

    dontConfigure = true;
    dontBuild = true;

    # The darwin binary is codesigned, and fixup (strip, install_name/patchelf
    # rewrites) would invalidate the signature. The Linux ones are static musl
    # and need nothing from fixup either, so it is off everywhere: the installed
    # binary stays byte-identical to the one in the attested archive.
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 hennery "$out/bin/hennery"
      install -Dm644 -t "$out/share/doc/hennery" LICENSE README.md CHANGELOG.md THIRD-PARTY-NOTICES.txt
      runHook postInstall
    '';

    meta = {
      description = "Collector and per-machine host for coding-agent sessions";
      homepage = "https://github.com/marcinwadon/hennery";
      license = lib.licenses.agpl3Only;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = builtins.attrNames archives;
      mainProgram = "hennery";
    };
  }
