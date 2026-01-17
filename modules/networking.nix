{ config, ... }:

{
  networking.useDHCP = true;

  networking.wireless = {
    enable = true;
    networks = {
      PontiFi = {
        psk = "to-be-replaced";
      };
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22 # SSH
      6443 # k3s API
    ];
  };
}
