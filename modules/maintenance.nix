{ config, pkgs, ... }:
{
  systemd.services.shutdown-at-night = {
    # Shutdown at night
    description = "Poweroff Service";
    startAt = [ "*-*-* 21:00:00" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/poweroff";
    };
    wantedBy = [ "default.target" ];
  };

  # systemctl status nixos-upgrade.(timer|service)
  # sudo systemctl start nixos-upgrade
  # journalctl -xeu nixos-upgrade.service
  # To see definition of service including ExecStart as script being run
  # cat /etc/systemd/system/nixos-upgrade.service
  system = {
    autoUpgrade = {
      enable = true;
      dates = "02:00";
      randomizedDelaySec = "45min";
      # Use the hostname to select the correct flake output
      flake = "github:damienpontifex/nixos-homelab#${config.networking.hostName}";
      flags = [
        "--no-update-lock-file" # We handle lock file updates ourselves
        "--show-trace" # Print build logs
        "--refresh" # Ensure we pull the latest flake info
      ];
      runGarbageCollection = true;
      operation = "switch";
      allowReboot = true;
    };
    activationScripts.diff = {
      supportsDryActivation = true;
      text = ''
        ${pkgs.nvd}/bin/nvd --nix-bin-dir=${pkgs.nix}/bin diff \
         /run/current-system "$systemConfig"
      '';
    };
  };

  nix = {
    settings.auto-optimise-store = true;

    # systemctl status nix-optimise.(timer|service)
    # journalctl -xeu nix-optimise.service
    optimise.automatic = true;

    # systemctl status nix-gc.(timer|service)
    # journalctl -xeu nix-gc.service
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
}
