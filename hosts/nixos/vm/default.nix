{
  imports = [
    ./hardware-configuration.nix
    ../../../modules # Imports common modules from modules/default.nix
    ../../../modules/disk-config.nix
    # ../../modules/k3s.nix  # K3s is optional, imported per-host
  ];

  # Disk configuration
  diskConfig.device = "/dev/vda";

  networking.hostName = "vm";
  networking.enableWifi = false;

  # Boot loader configuration for EFI systems
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
