{
  imports = [
    ./hardware-configuration.nix
    ../../../modules # Imports common modules from modules/default.nix
    ../../../modules/disk-config.nix
    ../../../modules/k3s.nix
  ];

  # Disk configuration
  diskConfig = {
    device = "/dev/sda";
    useSwap = false;
  };

  networking.hostName = "homeserver";

  # Boot loader configuration for EFI systems
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
