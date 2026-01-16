{
  imports = [
    ./hardware.nix
    ./disk-config.nix
    ../../modules  # Imports common modules from modules/default.nix
    # ../../modules/k3s.nix  # K3s is optional, imported per-host
    # ../../modules/auto-update.nix
  ];

  networking.hostName = "homeserver";

  # Boot loader configuration for EFI systems
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable automatic updates from git repository
  # services.nixos-auto-update = {
  #   enable = true;
  #   repository = "YOUR_GITHUB_USERNAME/nixos-homelab";  # TODO: Update with your GitHub username
  #   branch = "main";
  #   path = "/etc/nixos-config";
  #   autoRebuild = true;
  #   interval = "hourly";  # Check for updates every hour
  #   onBoot = true;        # Also check on boot
  # };
}
