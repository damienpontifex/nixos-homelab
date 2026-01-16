{ config, pkgs, lib, ... }:

let
  cfg = config.services.nixos-git-update;
  repoPath = "/etc/nixos-config";
in
{
  options.services.nixos-git-update = {
    enable = lib.mkEnableOption "automatic git repository cloning and updates";

    repository = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/damienpontifex/nixos-homelab.git";
      description = "Git repository URL to clone";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Git branch to track";
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = repoPath;
      description = "Local path where the repository will be cloned";
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure git is available
    environment.systemPackages = [ pkgs.git ];

    # Clone repository on first boot if it doesn't exist
    systemd.services.nixos-config-clone = {
      description = "Clone NixOS configuration repository";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        if [ ! -d "${cfg.path}/.git" ]; then
          echo "Cloning repository ${cfg.repository} to ${cfg.path}..."
          ${pkgs.git}/bin/git clone --branch ${cfg.branch} ${cfg.repository} ${cfg.path}
          echo "Repository cloned successfully"
        else
          echo "Repository already exists at ${cfg.path}"
        fi
      '';
    };

    # Update system.autoUpgrade to use the git repository
    system.autoUpgrade = {
      enable = true;
      # Use the hostname to select the correct flake output
      flake = "${cfg.path}#nixosConfigurations.${config.networking.hostName}";
      flags = [
        "--update-input" "nixpkgs"  # Update nixpkgs input
        "--commit-lock-file"         # Commit the updated lock file
        "-L"                         # Print build logs
      ];
      dates = "02:00";
      randomizedDelaySec = "45min";
      
      # Apply updates on next boot for safety
      operation = "boot";
    };

    # Systemd service to pull git changes before auto-upgrade
    systemd.services.nixos-upgrade.preStart = lib.mkBefore ''
      if [ -d "${cfg.path}/.git" ]; then
        echo "Pulling latest changes from ${cfg.repository}..."
        cd ${cfg.path}
        ${pkgs.git}/bin/git fetch origin ${cfg.branch}
        ${pkgs.git}/bin/git reset --hard origin/${cfg.branch}
        echo "Repository updated successfully"
      fi
    '';
  };
}
