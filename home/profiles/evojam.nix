let
  common = import ./common.nix;
in
  common
  // {
    enableBspCleanup = true;
    git = common.git // {userEmail = "mwadon@evojam.com";};
  }
