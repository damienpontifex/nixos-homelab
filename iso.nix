{ pkgs, modulesPath, ... }: {
  imports = [
    # This core module makes the resulting ISO a bootable installer
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Networking: Make sure you can connect to the internet immediately
  networking.networkmanager.enable = true;

  # Packages: List every program you want pre-installed on the ISO
  environment.systemPackages = with pkgs; [
    git vim firefox tailscale
  ];

  # Users: Add your SSH key so you can login remotely if needed
  users.users.nixos.openssh.authorizedKeys.keys = [ 
    "ssh-ed25519 AAAAC3..." 
  ];
}

