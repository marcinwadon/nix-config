let
  common = import ./common.nix;
in
  common
  // {
    enableBspCleanup = true;
    monitorMachine = "evojam";
    git = common.git // {userEmail = "mwadon@evojam.com";};
  }
