{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.k3s = {
    enable = true;
    role = lib.mkDefault "server";
    serverAddr = lib.mkDefault "";
    tokenFile = lib.mkDefault null;
    # version = "v1.26.4+k3s1";
    extraFlags = [
      "--disable traefik"
      "--disable servicelb"
      "--disable local-storage"
      "--disable-cloud-controller"
      "--disable-helm-controller"
    ];
  };

  # Automatically open firewall ports for k3s
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.k3s.enable [
    6443 # k3s API server
  ];

  networking.firewall.allowedUDPPorts = lib.mkIf config.services.k3s.enable [
    8472 # Flannel VXLAN
  ];

  environment.systemPackages = with pkgs; [
    kubectl
  ];
}
