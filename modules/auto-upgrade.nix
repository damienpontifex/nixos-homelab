{ config, ... }:
{
  # systemctl status nixos-upgrade.(timer|service)
  # To see definition of service including ExecStart as script being run
  # cat /etc/systemd/system/nixos-upgrade.service
  system.autoUpgrade = {
    enable = true;
    dates = "02:00";
    randomizedDelaySec = "45min";
    # Use the hostname to select the correct flake output
    # flake = inputs.self.outPath; TODO: Investigate this https://youtu.be/EI-6QX60WXc?si=HqmFp9RXB3FpjxGA&t=291
    flake = "github:damienpontifex/nixos-homelab#${config.networking.hostName}";
    flags = [
      "--no-update-lock-file" # We handle lock file updates ourselves
      "-L" # Print build logs
    ];
    runGarbageCollection = true;
    operation = "switch";
    allowReboot = true;
  };
}
