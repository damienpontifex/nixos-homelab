{ pkgs, modulesPath, ... }: {
  imports = [
    # This core module makes the resulting ISO a bootable installer
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Networking: Make sure you can connect to the internet immediately
  networking.networkmanager.enable = true;

  # Enable flakes for the installer environment
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Packages: List every program you want pre-installed on the ISO
  environment.systemPackages = with pkgs; [
    git
    vim
    firefox
    tailscale
    curl
    wget
  ];

  # Users: Add your SSH key so you can login remotely if needed
  users.users.nixos.openssh.authorizedKeys.keys = [ 
    "ssh-ed25519 AAAAC3..." 
  ];

  # Install script helper - creates a file with installation instructions
  environment.etc."nixos-install-from-git.sh" = {
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      echo "NixOS Installation from Git Repository"
      echo "======================================="
      echo ""
      echo "This script will help you install NixOS with git-tracked configuration."
      echo ""

      # Get repository URL
      read -p "Enter your git repository URL: " REPO_URL
      read -p "Enter hostname for this machine [nixos-machine]: " HOSTNAME
      HOSTNAME=''${HOSTNAME:-nixos-machine}

      # Partition and format disks
      echo ""
      echo "WARNING: This will erase your disk!"
      read -p "Enter the disk to install to (e.g., /dev/sda or /dev/nvme0n1): " DISK
      read -p "Are you sure you want to continue? (yes/no): " CONFIRM

      if [ "$CONFIRM" != "yes" ]; then
        echo "Installation cancelled."
        exit 1
      fi

      # Partition the disk (simple GPT + ESP + root)
      parted "$DISK" -- mklabel gpt
      parted "$DISK" -- mkpart ESP fat32 1MiB 512MiB
      parted "$DISK" -- set 1 esp on
      parted "$DISK" -- mkpart primary 512MiB 100%

      # Format partitions
      if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
        mkfs.fat -F 32 -n boot "''${DISK}p1"
        mkfs.ext4 -L nixos "''${DISK}p2"
        mount "''${DISK}p2" /mnt
        mkdir -p /mnt/boot
        mount "''${DISK}p1" /mnt/boot
      else
        mkfs.fat -F 32 -n boot "''${DISK}1"
        mkfs.ext4 -L nixos "''${DISK}2"
        mount "''${DISK}2" /mnt
        mkdir -p /mnt/boot
        mount "''${DISK}1" /mnt/boot
      fi

      # Clone the repository
      echo ""
      echo "Cloning configuration repository..."
      git clone "$REPO_URL" /mnt/etc/nixos
      cd /mnt/etc/nixos

      # Generate hardware configuration
      nixos-generate-config --root /mnt --no-filesystems
      mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hardware-configuration.nix

      # Update hostname in configuration.nix
      sed -i "s/networking.hostName = \"nixos-machine\";/networking.hostName = \"$HOSTNAME\";/" /mnt/etc/nixos/configuration.nix

      # Install
      echo ""
      echo "Installing NixOS..."
      nixos-install --flake /mnt/etc/nixos#$HOSTNAME --no-root-passwd

      echo ""
      echo "Installation complete!"
      echo "You can now reboot into your new system."
      echo ""
      echo "After booting, update your system with:"
      echo "  cd /etc/nixos && git pull && sudo nixos-rebuild switch --flake .#$HOSTNAME"
    '';
    mode = "0755";
  };
}

