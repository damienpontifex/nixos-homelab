{ config, lib, ... }:

{
  options = {
    networking.enableWifi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable wireless networking configuration";
    };
  };

  config = {
    networking.useDHCP = true;

    sops.secrets.pontiFiWiFiPassword = lib.mkIf config.networking.enableWifi { };

    networking.wireless = lib.mkIf config.networking.enableWifi {
      enable = true;
      networks = {
        PontiFi = {
          pskRaw = "ext:pontiFiWiFiPassword";
        };
      };
      secretsFile = config.sops.secrets.pontiFiWiFiPassword.path;
    };

    networking.firewall.enable = true;
  };
}
