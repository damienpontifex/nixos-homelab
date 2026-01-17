{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  # Boot loader is configured by nixos-hardware/raspberry-pi-4
  # Only keep hardware-specific filesystem configuration

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  swapDevices = [ ];
}
