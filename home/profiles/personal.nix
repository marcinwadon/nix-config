let
  common = import ./common.nix;
in
  common
  // {
    enableBspCleanup = true;
    monitorMachine = "personal";
    git = common.git // {userEmail = "marcin.wadon@gmail.com";};
  }
