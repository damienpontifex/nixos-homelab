{ config, ... }:
{
  system.autoUpgrade = {
    enable = true;
    # Use the hostname to select the correct flake output
    flake = "github:damienpontifex/nixos-homelab#${config.networking.hostName}";
    flags = [
      "--no-update-lock-file" # We handle lock file updates ourselves
      "-L" # Print build logs
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
    runGarbageCollection = true;
    operation = "switch";
    allowReboot = true;
  };
}
