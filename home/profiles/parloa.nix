let
  common = import ./common.nix;
in
  common
  // {
    git = common.git // {userEmail = "244477798+marcin-wadon-parloa@users.noreply.github.com";};
  }
