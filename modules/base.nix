{ config, pkgs, ... }:

{
  # Enable flakes on deployed systems (for local nixos-rebuild operations)
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    just
    neovim
  ];

  nixpkgs.config.allowUnfree = true;

  nix.optimise.automatic = true;
  nix.settings.auto-optimise-store = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  system.stateVersion = "25.11";
}
