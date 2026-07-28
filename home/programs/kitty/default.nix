{
  pkgs,
  lib,
  ...
}: let
  # The palette carried over verbatim from the old hand-managed
  # ~/.config/kitty/current-theme.conf (an Ayu-dark variant). Kept literal rather
  # than swapped for `themeFile = "ayu"` — the shipped Ayu differs (#0f1419 vs
  # #0e1419 background) and recolouring the terminal isn't the point of this change.
  theme = {
    background = "#0e1419";
    foreground = "#e5e1cf";
    cursor = "#f19618";
    selection_background = "#243340";
    selection_foreground = "#0e1419";

    color0 = "#000000";
    color8 = "#323232";
    color1 = "#ff3333";
    color9 = "#ff6565";
    color2 = "#b8cc52";
    color10 = "#e9fe83";
    color3 = "#e6c446";
    color11 = "#fff778";
    color4 = "#36a3d9";
    color12 = "#68d4ff";
    color5 = "#f07078";
    color13 = "#ffa3aa";
    color6 = "#95e5cb";
    color14 = "#c7fffc";
    color7 = "#ffffff";
    color15 = "#ffffff";
  };
in {
  # Darwin-only: the Linux containers are headless and need no terminal emulator.
  # `mkIf` gates a *value*, never `imports` — a config-dependent import would
  # cause infinite recursion (same pattern as `programs.gpg` in ../default.nix).
  programs.kitty = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;

    # The package comes from nix-darwin's `environment.systemPackages` instead of
    # here, so one derivation provides both the GUI bundle (aliased into
    # /Applications/Nix Apps) and `kitty`/`kitten` on PATH. Splitting them would
    # let the app and the kittens drift apart on the next `nix flake update`, and
    # kitty expects the two to be the same version. Home Manager owns config only.
    package = null;

    font = {
      name = "MesloLGS NF Bold";
      size = 13;
    };

    # Wires `kitten diff` in as git's difftool (diff.tool + difftool.kitty.cmd).
    # No collision with ../git: that sets merge.tool/mergetool, not diff.tool.
    enableGitIntegration = true;

    settings =
      {
        macos_option_as_alt = "left";

        # Nix owns the version; kitty's own update nag is noise.
        update_check_interval = 0;

        # `kitty @ …` (launch windows, send-text, set-colors from scripts).
        # socket-only deliberately excludes the escape-code control surface, so
        # remote or untrusted terminal output cannot drive the terminal.
        allow_remote_control = "socket-only";
        listen_on = "unix:/tmp/kitty";

        # macOS notification when a command slower than 10s finishes unfocused —
        # sized for `nixos-rebuild` / `nix build`. This rides shell-integration
        # OSC 133 marks, which tmux may swallow; UNVERIFIED inside tmux. If it
        # stays silent there, append `kitten notify done` to the command instead.
        notify_on_cmd_finish = "unfocused 10.0";
      }
      // theme;

    # No hints bindings here on purpose: kitty already ships them all under
    # kitty_mod (= ctrl+shift) — ctrl+shift+e opens a URL, and p>f path,
    # p>h git hash, p>l line, p>w word all copy to the clipboard, while
    # p>n opens a file:line match in $EDITOR at that line.
    keybindings = {
      # Claude Code and friends need a real newline on shift+enter.
      "shift+enter" = "send_text all \\e\\r";
    };
  };
}
