{ config, pkgs, ... }:

{
  # Enable flakes on deployed systems (for local nixos-rebuild operations)
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    neovim
  ];

  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "25.11";
}
