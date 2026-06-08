{inputs, ...}: let
  system = "x86_64-linux";
  homeConf = import ./home-conf.nix {inherit inputs;};
  overlays = homeConf.mkOverlays system;
  # neovim-flake module is Darwin-only (see home/programs/default.nix); Linux
  # containers use a plain nixpkgs neovim, so no extra home-manager modules here.
  homeModules = [];

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
  monitor = mkEnv "monitor" (import ../home/profiles/monitor.nix);
}
