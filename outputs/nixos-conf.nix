{ inputs, ... }:

let
  nixosSystem = inputs.nixpkgs.lib.nixosSystem;
in
{
  nixos = nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      ../system/machine/nixos
      ../system/configuration.nix
    ];
  };
}
