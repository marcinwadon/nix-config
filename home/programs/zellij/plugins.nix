{pkgs, ...}: {
  zellij-autolock = pkgs.fetchurl {
    url = "https://github.com/fresh2dev/zellij-autolock/releases/download/0.2.2/zellij-autolock.wasm";
    hash = "sha256-aclWB7/ZfgddZ2KkT9vHA6gqPEkJ27vkOVLwIEh7jqQ=";
  };

  zjstatus = pkgs.fetchurl {
    url = "https://github.com/dj95/zjstatus/releases/download/v0.22.0/zjstatus.wasm";
    hash = "sha256-TeQm0gscv4YScuknrutbSdksF/Diu50XP4W/fwFU3VM=";
  };

  ghost = pkgs.fetchurl {
    url = "https://github.com/vdbulcke/ghost/releases/download/v0.7.1/ghost.wasm";
    hash = "sha256-uL1hAdAfvZr9181n5WDn2pr6n1R2gY/jbV9/6C0L0OA=";
  };

  harpoon = pkgs.fetchurl {
    url = "https://github.com/Nacho114/harpoon/releases/download/v0.2.1/harpoon.wasm";
    hash = "sha256-J9KuuIP+tyjaNvC+B3dJFQhLQ0ye5WAnnvI6xLfuOOg=";
  };

  zellij-choose-tree = pkgs.fetchurl {
    url = "https://github.com/laperlej/zellij-choose-tree/releases/download/v0.4.2/zellij-choose-tree.wasm";
    hash = "sha256-OGHLzCM9wg0CLm5SSr3bmElcciBIqamalQjgkTuzAeg=";
  };
}
