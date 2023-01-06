{ inputs, ... }:

let
  darwinSystem = inputs.darwin.lib.darwinSystem;
in
{
  macos = darwinSystem {
    system = "aarch64-darwin";
    specialArgs = { inherit inputs; };
    modules = [
      ../system/machine/macos
      ../system/configuration-darwin.nix
    ];
  };
}

