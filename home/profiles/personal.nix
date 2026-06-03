let
  common = import ./common.nix;
in
  common
  // {
    enableBspCleanup = true;
    git = common.git // {userEmail = "marcin.wadon@gmail.com";};
  }
