{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../modules # Imports common modules from modules/default.nix
    # ../../modules/k3s.nix  # K3s is optional, imported per-host
  ];

  networking.hostName = "homeserver";

  # Boot loader configuration for EFI systems
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable automatic updates from git repository
  services.nixos-git-update = {
    enable = true;
    repository = "https://github.com/damienpontifex/nixos-homelab.git";
    branch = "main";
  };
}
