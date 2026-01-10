{ config, pkgs, ... }:

{
  # Enable flakes on deployed systems (for local nixos-rebuild operations)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "24.11";

  environment.systemPackages = with pkgs; [
    neovim
    git
    curl
    htop
  ];
}
