let
  common = import ./common.nix;
in
  common
  // {
    enableConstellationScripts = true;
    enableBspCleanup = true;
    git = common.git // {userEmail = "marcin.wadon@gmail.com";};
  }
