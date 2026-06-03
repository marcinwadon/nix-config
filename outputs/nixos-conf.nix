{inputs, ...}: let
  system = "x86_64-linux";
  homeConf = import ./home-conf.nix {inherit inputs;};
  overlays = homeConf.mkOverlays system;
  homeModules = [inputs.neovim-flake.homeManagerModules.${system}.default];

  mkEnv = name: profile:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs overlays homeModules profile;};
      modules = [../nixos/envs/${name}.nix];
    };
in {
  personal = mkEnv "personal" (import ../home/profiles/personal.nix);
  evojam = mkEnv "evojam" (import ../home/profiles/evojam.nix);
  parloa = mkEnv "parloa" (import ../home/profiles/parloa.nix);
}
