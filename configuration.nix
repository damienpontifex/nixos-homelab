# Main NixOS configuration for your installed system
# This file will be deployed to /etc/nixos/configuration.nix after installation
{ config, pkgs, ... }:

{
  imports = [
    # Hardware configuration (generated during installation)
    ./hardware-configuration.nix
  ];

  # Boot loader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "nixos-machine";
  networking.networkmanager.enable = true;

  # Time zone and locale
  time.timeZone = "America/New_York";  # Adjust to your timezone
  i18n.defaultLocale = "en_US.UTF-8";

  # Enable flakes and nix-command (required for modern NixOS workflow)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # System packages
  environment.systemPackages = with pkgs; [
    git
    vim
    firefox
    tailscale
    curl
    wget
    htop
  ];

  # Enable SSH for remote access
  services.openssh.enable = true;

  # User configuration
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [ 
      "ssh-ed25519 AAAAC3..." 
    ];
    # Set a password or use initialPassword for first login
    # initialPassword = "changeme";
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;  # Change to true for production

  # Tailscale service
  services.tailscale.enable = true;

  # Automatic garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Auto-upgrade system (pulls from this git repo)
  # Uncomment after setting up your git repository
  # system.autoUpgrade = {
  #   enable = true;
  #   flake = "github:yourusername/nixos-build#nixos-machine";
  #   dates = "daily";
  #   allowReboot = false;
  # };

  # This value determines the NixOS release compatibility
  # DO NOT CHANGE this value unless upgrading NixOS versions
  system.stateVersion = "24.11";  # Adjust to your NixOS version
}
