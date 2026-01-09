{ config, ... }:

{
  networking.useDHCP = true;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    22    # SSH
    6443  # k3s API
  ];
}
