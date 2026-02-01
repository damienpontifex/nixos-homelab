{
  config,
  pkgs,
  lib,
  ...
}:
let
  userConfig = config.users.users.ponti;
  pontiHome = userConfig.home;

  copyKubeconfigScript = pkgs.writeShellApplication {
    name = "copy-k3s-config";
    runtimeInputs = [ pkgs.coreutils ]; # Adds these to the script's PATH
    text = ''
      while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
        sleep 1
      done
      mkdir -p "${pontiHome}/.kube"
      cp /etc/rancher/k3s/k3s.yaml "${pontiHome}/.kube/config"
      chown ${userConfig.name}:users /home/user/.kube/config
      chmod 600 "${pontiHome}/.kube/config"
    '';
  };
in
{
  # Configure sops secret for k3s token
  sops.secrets.k3s-token = lib.mkIf config.services.k3s.enable {
    sopsFile = ../secrets.yaml;
  };

  environment.systemPackages = with pkgs; [
    # cilium status && cilium connectivity test
    cilium-cli
    kubectl
  ];

  # systemctl status rke2-server
  # journalctl -xeu rke2-server
  services.rke2 = {
    enable = false;
    role = lib.mkDefault "server";
    cni = "cilium";
    tokenFile = lib.mkIf config.services.rke2.enable (lib.mkDefault config.sops.secrets.k3s-token.path);
    configPath = "/etc/rancher/rke2/config.yaml";
  };

  # NetworkManager: Ignore CNI-managed interfaces
  ## [As the official documentation for RKE2 requires at the time of writing this](https://docs.rke2.io/known_issues#networkmanager)
  networking.networkmanager.unmanaged = [
    "interface-name:cni*"
    "interface-name:flannel*"
    "interface-name:veth*"
    "interface-name:cali*"
    "interface-name:tunl*"
  ];

  programs.bash.shellAliases = lib.mkIf config.services.rke2.enable {
    k = "kubectl --kubeconfig=/etc/rancher/rke2/rke2.yaml";
  };

  systemd.services.copy-k3s-config = {
    description = "Copy k3s kubeconfig and adjust server address";
    after = [ "k3s.service" ];
    requires = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${copyKubeconfigScript}";
    };
  };

  environment.etc."rancher/rke2/config.yaml" = {
    text = ''
      tls-san:
        - ${config.networking.hostName}.local
        - k8s.pontifex.dev
      write-kubeconfig-mode: 600
    '';
    mode = "0600";
  };
  # To get the kubeconfig from the k3s server and replace the server address:
  # `just homelab-kubeconfig`
  services.k3s = {
    enable = true;
    role = lib.mkDefault "server";
    serverAddr = lib.mkDefault "";
    tokenFile = lib.mkIf config.services.k3s.enable (lib.mkDefault config.sops.secrets.k3s-token.path);
    # version = "v1.26.4+k3s1";
    extraFlags = [
      "--disable-cloud-controller"
      "--tls-san ${config.networking.hostName}.local"
      "--tls-san k8s.pontifex.dev"
      "--kube-apiserver-arg=anonymous-auth=true"
      "--kube-apiserver-arg=service-account-issuer=https://homelab.pontifex.dev"
      "--kube-apiserver-arg=service-account-jwks-uri=https://homelab.pontifex.dev/openid/v1/jwks"
      "--write-kubeconfig-mode=0664"
      # Cilium
      # "--flannel-backend=none" # Disable Flannel to use Cilium
      # "--disable-kube-proxy" # Let Cilium handle kube-proxy functionality
      # "--disable-network-policy" # Let Cilium handle network policies
    ];
    disable = [
      # "traefik"
      # "servicelb"
      # "local-storage"
    ];
    gracefulNodeShutdown.enable = true;

    # autoDeployCharts.cilium = lib.mkIf (config.services.k3s.role == "server") {
    #   name = "cilium";
    #   # https://artifacthub.io/packages/helm/cilium/cilium
    #   repo = "https://helm.cilium.io/";
    #   # renovate: datasource=helm registryUrl=https://helm.cilium.io depName=cilium
    #   version = "1.18.6";
    #   hash = "sha256-+yr38lc5X1+eXCFE/rq/K0m4g/IiNFJHuhB+Nu24eUs=";
    #   targetNamespace = "kube-system";
    #   createNamespace = false; # kube-system already exists
    #   values = {
    #     # Basic k3s integration settings
    #     # Required for kube-proxy replacement to work correctly
    #     k8sServiceHost = "localhost";
    #     k8sServicePort = "6443";
    #
    #     # Use native routing (no encapsulation) for best performance
    #     routingMode = "native";
    #     autoDirectNodeRoutes = true;
    #     ipv4NativeRoutingCIDR = "10.42.0.0/16"; # k3s default pod CIDR
    #
    #     # Enable eBPF-based kube-proxy replacement for better performance
    #     kubeProxyReplacement = true;
    #
    #     operator = {
    #       replicas = 1;
    #     };
    #
    #     # Enable Hubble for network observability
    #     hubble = {
    #       relay.enabled = true;
    #       ui.enabled = true;
    #     };
    #
    #     # BGP Control Plane (for future BGP integration if needed)
    #     bgpControlPlane.enabled = true;
    #   };
    #   # Enable bootstrap mode to install Cilium before the Kubernetes API is fully available
    #   # This is equivalent to what staticContentPort does in the nixpkgs k3s module
    #   extraFieldDefinitions = {
    #     spec.bootstrap = true;
    #   };
    # };

    autoDeployCharts.argocd = lib.mkIf (config.services.k3s.role == "server") {
      name = "argocd";
      # https://artifacthub.io/packages/helm/argo-cd-oci/argo-cd
      repo = "oci://ghcr.io/argoproj/argo-helm/argo-cd";
      # renovate: datasource=helm registryUrl=https://argoproj.github.io/argo-helm depName=argo-cd
      version = "9.3.4";
      hash = "sha256-dpTJFsJgs8rZU3ejxgyggLSpeYGGZnFTPLeQVMV0wG0=";
      targetNamespace = "argocd";
      createNamespace = true;
      values = {
        global = {
          domain = "argocd.home.pontifex.dev";
        };
        server = {
          ingress = {
            enabled = true;
            ingressClassName = "traefik";
            tls = true;
            annotations = {
              "cert-manager.io/cluster-issuer" = "letsencrypt-prod";
            };
          };
        };
        configs = {
          params = {
            "server.insecure" = "true";
          };
          cm = {
            "kustomize.buildOptions" = "--enable-helm";
            "accounts.gethomepage" = "apiKey";
          };
          rbac = {
            "policy.default" = "role:readonly";
            "policy.csv" = ''
              p, gethomepage, *, *, *, role:readonly
            '';
          };
        };
      };
    };

    # Bootstrap ArgoCD Application for Homelab
    manifests = {
      homelab-application = {
        enable = true;
        target = "homelab-application.yaml";
        content = {
          apiVersion = "argoproj.io/v1alpha1";
          kind = "Application";
          metadata = {
            name = "homelab";
            namespace = "argocd";
          };
          spec = {
            project = "homelab";
            source = {
              repoURL = "https://github.com/damienpontifex/homelab";
              path = "apps/";
              directory = {
                recurse = true;
                include = "*/application.yaml";
              };
            };
            destination = {
              name = "in-cluster";
              namespace = "default";
            };
            syncPolicy = {
              automated = {
                enabled = true;
                prune = true;
                selfHeal = true;
              };
              syncOptions = [
                "ServerSideApply=true"
                "CreateNamespace=true"
              ];
              retry = {
                limit = 2;
                backoff = {
                  duration = "5s";
                  factor = 2;
                  maxDuration = "3m";
                };
              };
            };
          };
        };
      };
      homelab-project = {
        enable = true;
        target = "homelab-project.yaml";
        content = {
          apiVersion = "argoproj.io/v1alpha1";
          kind = "AppProject";
          metadata = {
            name = "homelab";
            namespace = "argocd";
          };
          spec = {
            description = "pontifex.dev Homelab";
            # Allow manifests to deploy from any Git repos under damienpontifex GitHub account
            sourceRepos = [
              # "https://github.com/damienpontifex/*"
              # "https://jameswynn.github.io/helm-charts" # homepage
              # "https://charts.external-secrets.io"
              # "https://kyverno.github.io/kyverno"
              # "https://kubernetes.github.io/*"
              "*"
            ];
            # Allow deployment to any namespace on the cluster
            destinations = [
              {
                namespace = "*";
                server = "*";
              }
            ];
            clusterResourceWhitelist = [
              {
                group = "*";
                kind = "*";
              }
            ];
          };
        };
      };
    };
  };

  # Automatically open firewall ports for k3s
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.k3s.enable [
    6443 # k3s API server
    4244 # Cilium health checks
    4245 # Cilium Hubble relay
  ];

  networking.firewall.allowedUDPPorts = lib.mkIf config.services.k3s.enable [
    # 8472 # Flannel VXLAN: no longer needed with native routing
    4240 # Cilium health checks (UDP)
  ];
}
