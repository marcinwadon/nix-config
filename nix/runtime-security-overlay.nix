# CVE-2026-111497: update Node and, where used, its shared Brotli decoder.
# Keep the existing pnpm and browser package sets at their locked revisions.
final: prev: let
  brotli = prev.brotli.overrideAttrs (_old: {
    version = "1.2.1";
    src = prev.fetchFromGitHub {
      owner = "google";
      repo = "brotli";
      rev = "v1.2.1";
      hash = "sha256-llY72cYffDv0ugsH0p89xIPEbElV4L8u7U/Fe8hT3gI=";
    };
    # The old LoongArch/IA64 patch is already included in this release.
    patches = [];
  });
  secureNode = package: version: sha256:
    package.override {
      callPackage = path: args:
        if builtins.baseNameOf path != "nodejs.nix"
        then prev.callPackage path args
        else
          nodeArgs:
            (prev.callPackage path (args
              // prev.lib.optionalAttrs
              (builtins.functionArgs (import path) ? brotli) {inherit brotli;})) (nodeArgs
              // {
                inherit version sha256;
                # These patches are already included in the patched releases.
                patches =
                  builtins.filter
                  (patch:
                    !(version
                      == "24.22.1"
                      && (
                        builtins.baseNameOf (toString patch)
                        == "configure-emulator.patch"
                        || prev.lib.hasInfix "4a32c00fb8dbe55c3bcf9ef43343968c9fe449e6" (toString patch)
                      )))
                  (nodeArgs.patches or []);
              });
    };
in {
  nodejs-slim_22 =
    secureNode prev.nodejs-slim_22 "22.23.4"
    "7b9adc82d612d0a2a863d96c46de2292552e250cee51956ebbe0146c42aacae9";
  nodejs-slim_24 =
    secureNode prev.nodejs-slim_24 "24.22.1"
    "4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";
}
