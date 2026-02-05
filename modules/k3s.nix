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
      chown ${userConfig.name}:users "${pontiHome}/.kube/config"
      chmod 600 "${pontiHome}/.kube/config"
    '';
  };
in
{
  # Configure sops secret for k3s token
  sops.secrets.k3s-token = lib.mkIf config.services.k3s.enable {
    sopsFile = ../secrets.yaml;
  };

  sops.secrets.cloudflare-token = lib.mkIf config.services.k3s.enable {
    sopsFile = ../secrets.yaml;
  };

  # Create a template for the cloudflare token secret
  sops.templates."cloudflare-token-secret.yaml" = lib.mkIf config.services.k3s.enable {
    content = ''
      apiVersion: v1
      kind: Secret
      metadata:
        name: cloudflare-tunnel-token
        namespace: cloudflare-tunnel
      type: Opaque
      stringData:
        token: ${config.sops.placeholder.cloudflare-token}
    '';
    owner = userConfig.name;
    mode = "0600";
  };

  environment.systemPackages = with pkgs; [
    # cilium status && cilium connectivity test
    cilium-cli
    kubectl
    kubernetes-helm
  ];

  programs.bash.shellAliases = lib.mkIf config.services.k3s.enable {
    k = "kubectl";
    kgp = "kubectl get pods";
  };

  systemd.services.copy-k3s-config = {
    description = "Copy k3s kubeconfig and adjust server address";
    after = [ "k3s.service" ];
    requires = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${copyKubeconfigScript}/bin/${copyKubeconfigScript.name}";
    };
  };

  # Automatically open firewall ports for k3s
  networking.firewall.allowedTCPPorts = lib.mkIf config.services.k3s.enable [
    6443 # k3s API server
  ];

  networking.firewall.allowedUDPPorts = lib.mkIf config.services.k3s.enable [
    8472 # k3s: flannel: required if using multi-node for intern-node networking
  ];

  # To get the kubeconfig from the k3s server and replace the server address:
  # `just homelab-kubeconfig`
  # Guide https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/cluster/k3s/README.md
  # If wanting to remove https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/cluster/k3s/docs/CLUSTER_UPKEEP.md
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
          serviceAccount = {
            annotations = {
              "azure.workload.identity/client-id" = "ea227ff8-7b75-4f0f-83a9-7638e949faf3";
              "azure.workload.identity/tenant-id" = "ff2b9041-8733-4fbd-a4e6-23f30567c4a4";
            };
          };
          podLabels = {
            "azure.workload.identity/use" = "true";
          };
        };
        configs = {
          params = {
            "server.insecure" = "true";
          };
          cm = {
            "kustomize.buildOptions" = "--enable-helm";
            "accounts.gethomepage" = "apiKey";
            "oidc.config" = ''
              name: SSO
              issuer: https://login.microsoftonline.com/ff2b9041-8733-4fbd-a4e6-23f30567c4a4/v2.0
              clientID: ea227ff8-7b75-4f0f-83a9-7638e949faf3
              azure:
                useWorkloadIdentity: true
              requestedScopes:
                - openid
                - profile
                - email
            '';
          };
          rbac = {
            "policy.default" = "role:readonly";
            "policy.csv" = ''
              p, gethomepage, applications, *, */*, role:readonly
              p, role:org-admin, applications, *, */*, allow
              p, role:org-admin, clusters, get, *, allow
              p, role:org-admin, repositories, get, *, allow
              p, role:org-admin, repositories, create, *, allow
              p, role:org-admin, repositories, update, *, allow
              p, role:org-admin, repositories, delete, *, allow
              g, 01c9f9ea-c5b3-4e43-a2f8-d60fa4ba6d8d, role:admin
              g, damien.pontifex@gmail.com, role:org-admin
            '';
            scopes = "[groups, email]";
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
      cloudflare-namespace = {
        target = "cloudflare-namespace.yaml";
        content = {
          apiVersion = "v1";
          kind = "Namespace";
          metadata = {
            name = "cloudflare-tunnel";
          };
        };
      };
      cloudflare-token-secret = {
        target = "cloudflare-token-secret.yaml";
        # Use the sops template instead of trying to read the file directly
        source = config.sops.templates."cloudflare-token-secret.yaml".path;
      };
    };
  };
}
