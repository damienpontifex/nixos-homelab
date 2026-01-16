{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nixos-auto-update;
  
  repoUrl = "https://github.com/${cfg.repository}";
  configPath = cfg.path;
  
  updateScript = pkgs.writeShellScript "nixos-auto-update" ''
    set -euo pipefail
    
    echo "[$(date)] Starting NixOS auto-update from ${repoUrl}"
    
    # Ensure the directory exists
    if [ ! -d "${configPath}" ]; then
      echo "Config directory doesn't exist, cloning repository..."
      ${pkgs.git}/bin/git clone ${repoUrl} ${configPath}
      cd ${configPath}
    else
      cd ${configPath}
      
      # Check if it's a git repository
      if [ ! -d .git ]; then
        echo "ERROR: ${configPath} exists but is not a git repository!"
        exit 1
      fi
      
      # Fetch latest changes
      ${pkgs.git}/bin/git fetch origin
      
      # Check if there are updates
      LOCAL=$(${pkgs.git}/bin/git rev-parse HEAD)
      REMOTE=$(${pkgs.git}/bin/git rev-parse origin/${cfg.branch})
      
      if [ "$LOCAL" = "$REMOTE" ]; then
        echo "Already up to date (commit: $LOCAL)"
        ${optionalString (!cfg.alwaysRebuild) "exit 0"}
      else
        echo "Updates available: $LOCAL -> $REMOTE"
        ${pkgs.git}/bin/git pull origin ${cfg.branch}
      fi
    fi
    
    ${optionalString cfg.autoRebuild ''
      echo "Rebuilding NixOS configuration..."
      ${pkgs.nixos-rebuild}/bin/nixos-rebuild switch --flake ${configPath}#${cfg.hostname}
      echo "NixOS rebuild completed successfully"
    ''}
    
    echo "[$(date)] Auto-update completed"
  '';
in
{
  options.services.nixos-auto-update = {
    enable = mkEnableOption "automatic NixOS configuration updates from git";
    
    repository = mkOption {
      type = types.str;
      example = "username/nixos-homelab";
      description = "GitHub repository in the format 'username/repo'";
    };
    
    branch = mkOption {
      type = types.str;
      default = "main";
      description = "Git branch to track";
    };
    
    path = mkOption {
      type = types.str;
      default = "/etc/nixos-config";
      description = "Path where the configuration repository will be cloned";
    };
    
    hostname = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Hostname to use in the flake configuration (e.g., 'homeserver')";
    };
    
    autoRebuild = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically run nixos-rebuild switch after pulling changes";
    };
    
    alwaysRebuild = mkOption {
      type = types.bool;
      default = false;
      description = "Run nixos-rebuild even if there are no git changes (useful for testing)";
    };
    
    interval = mkOption {
      type = types.str;
      default = "hourly";
      description = "How often to check for updates (systemd timer format)";
    };
    
    onBoot = mkOption {
      type = types.bool;
      default = true;
      description = "Run update check on system boot";
    };
  };
  
  config = mkIf cfg.enable {
    # Install git globally
    environment.systemPackages = [ pkgs.git ];
    
    # Clone repository on first activation if it doesn't exist
    system.activationScripts.cloneNixosConfig = lib.mkIf (!builtins.pathExists configPath) ''
      if [ ! -d "${configPath}" ]; then
        echo "Cloning NixOS configuration from ${repoUrl}..."
        ${pkgs.git}/bin/git clone ${repoUrl} ${configPath}
        echo "Configuration cloned to ${configPath}"
      fi
    '';
    
    # Systemd service to perform the update
    systemd.services.nixos-auto-update = {
      description = "NixOS automatic configuration update from git";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${updateScript}";
      };
      path = with pkgs; [ git nixos-rebuild nix ];
      environment = {
        NIX_CONFIG = "experimental-features = nix-command flakes";
      };
    };
    
    # Systemd timer to trigger the service
    systemd.timers.nixos-auto-update = {
      description = "Timer for NixOS automatic updates";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        OnBootSec = mkIf cfg.onBoot "5min";
        Persistent = true;
      };
    };
  };
}
