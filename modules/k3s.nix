{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Configure sops secret for k3s token
  sops.secrets.k3s-token = lib.mkIf config.services.k3s.enable {
    sopsFile = ../secrets.yaml;
  };

  # On NixOS
  # sudo k3s kubectl config view --raw > ~/.kube/config
  # On local
  # scp user@host:~/.kube/config ~/.kube/config
  services.k3s = {
    enable = true;
    role = lib.mkDefault "server";
    serverAddr = lib.mkDefault "";
    tokenFile = lib.mkIf config.services.k3s.enable (lib.mkDefault config.sops.secrets.k3s-token.path);
    # version = "v1.26.4+k3s1";
    extraFlags = [
      #   "--disable traefik"
      #   "--disable servicelb"
      #   "--disable local-storage"
      #   "--disable-cloud-controller"
      #   "--disable-helm-controller"
    ];

    autoDeployCharts.argocd = lib.mkIf (config.services.k3s.role == "server") {
      name = "argocd";
      repo = "oci://ghcr.io/argoproj/argo-helm/argo-cd";
      # renovate: datasource=helm registryUrl=https://argoproj.github.io/argo-helm depName=argo-cd
      version = "9.3.4";
      hash = "sha256-dpTJFsJgs8rZU3ejxgyggLSpeYGGZnFTPLeQVMV0wG0=";
      targetNamespace = "argocd";
      createNamespace = true;
      values = {
        configs = {
          cm = {
            "kustomize.buildOptions" = "--enable-helm";
          };
        };
      };
    };
  };

  # Automatically open firewall ports for k3s
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.k3s.enable [
    6443 # k3s API server
  ];

  networking.firewall.allowedUDPPorts = lib.mkIf config.services.k3s.enable [
    8472 # Flannel VXLAN: required if using multi-node for inter-node networking
  ];

  environment.systemPackages = with pkgs; [
    kubectl
  ];
}
