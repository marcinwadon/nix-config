{ pkgs, ... }:

let
  tmux = "${pkgs.tmux}/bin/tmux";
in
pkgs.writeShellScriptBin "close" ''
  ${tmux} kill-session -t $1
''

