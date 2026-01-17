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

    sops.secrets.pontiFiWiFiPassword = lib.mkIf config.networking.enableWifi { };

    networking = {
      useDHCP = true;
      firewall.enable = true;
      wireless = lib.mkIf config.networking.enableWifi {
        enable = true;
        networks = {
          PontiFi = {
            pskRaw = "ext:pontiFiWiFiPassword";
          };
        };
        secretsFile = config.sops.secrets.pontiFiWiFiPassword.path;
      };
    };
  };
}
