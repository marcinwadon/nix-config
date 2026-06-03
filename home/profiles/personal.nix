let
  common = import ./common.nix;
in
  common
  // {
    enableConstellationScripts = true;
    enableBspCleanup = true;
    git = common.git // {userEmail = "PERSONAL_EMAIL_PLACEHOLDER";};
  }
