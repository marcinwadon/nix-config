# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal Nix configuration repository managing macOS (Darwin) systems using modern Nix Flakes, Home Manager, and nix-darwin. The configuration has been modernized to focus exclusively on macOS development with clean, maintainable patterns.

## Architecture

### Core Structure
- **flake.nix**: Main entry point with modern flake inputs and outputs including formatter and devShells
- **outputs/**: Configuration builders streamlined for Darwin-only usage
  - `home-conf.nix`: Builds home-manager configuration for macOS (aarch64-darwin)
  - `darwin-conf.nix`: Builds macOS system configuration using nix-darwin
- **home/**: Home-manager configuration and user environment
  - `home.nix`: Main home configuration with user settings and package lists
  - `programs/`: Modular program configurations (git, fish, tmux, neovim, etc.)
  - `scripts/`: Custom shell scripts packaged as Nix derivations
  - `secrets/`: SSH and other sensitive configuration files
- **system/**: System-level configurations
  - `configuration-darwin.nix`: macOS system settings with modern optimizations
  - `machine/macos/`: macOS-specific machine configuration

### Modern Features
- **Apple Silicon focused**: Optimized exclusively for aarch64-darwin
- **Modern overlay patterns**: Uses proper flake inputs instead of fetchTarball
- **Development environment**: Includes devShells and direnv integration
- **Formatter integration**: Built-in alejandra formatter support
- **Streamlined structure**: Removed unnecessary cross-platform abstractions

## Common Development Commands

### Building and Switching Configurations

**Home Manager (user environment)**:
```bash
# Build and switch home configuration
./switch home

# Update fish completions
./switch update-fish
```

**System Configuration (Darwin)**:
```bash
# Build and switch system configuration
./switch darwin

# Or use darwin-rebuild directly
darwin-rebuild switch --flake .
```

### Flake Management

```bash
# Update all flake inputs
nix flake update

# Check flake for issues
nix flake check

# Show flake info
nix flake show
```

### Package Management

```bash
# Search for packages
nix search nixpkgs <package-name>

# Test package without installing
nix shell nixpkgs#<package-name>

# Build home configuration
nix build .#homeConfigurations.marcinwadon.activationPackage

# Format code
nix fmt
```

### Maintenance

```bash
# Clean old generations manually
nix-collect-garbage -d

# Optimize nix store
nix store optimise
```

## Configuration Profiles

- **marcinwadon**: Home configuration for macOS (aarch64-darwin)
- **macos**: System configuration for macOS using nix-darwin

## Development Environment

The repository includes a development shell accessible via:
```bash
# Enter development environment (with direnv)
direnv allow

# Or manually
nix develop
```

This provides tools for managing the Nix configuration including nix, home-manager, git, and alejandra formatter.

## Custom Scripts

Located in `home/scripts/`, these are packaged as Nix derivations:
- **clean-bsp-workspace**: Cleans BSP workspace files
- **tmux-close**: Tmux session management
- **h_mainnet**, **h_testnet**, **h_integrationnet**: Network-specific utility scripts

## Special Files

- **switch**: Main deployment script with modernized commands (home/darwin)
- **public.gpg**: GPG public key for secrets management
- **.envrc**: Direnv configuration for automatic development environment loading
- **home/programs/neovim-ide/update-metals.nix**: Automated Metals language server updater for Scala development

## Development Tools Included

- **claude-code**: AI-powered development assistant
- **neovim**: Configured as full IDE with LSP support
- **tmux**: Terminal multiplexer with custom plugins
- **fish**: Shell with custom theme and completions  
- **git**: Version control with GPG signing
- **Development utilities**: gh, ripgrep, fd, fzf, direnv, cachix, and more