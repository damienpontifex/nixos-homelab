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

  # To get the kubeconfig from the k3s server and replace the server address:
  # `just homelab-kubeconfig`
  services.k3s = {
    enable = true;
    role = lib.mkDefault "server";
    serverAddr = lib.mkDefault "";
    tokenFile = lib.mkIf config.services.k3s.enable (lib.mkDefault config.sops.secrets.k3s-token.path);
    # version = "v1.26.4+k3s1";
    extraFlags = [
      #   "--disable-cloud-controller"
      "--tls-san ${config.networking.hostName}.local"
      "--tls-san k8s.pontifex.dev"
      "--kube-apiserver-arg=anonymous-auth=true"
      "--kube-apiserver-arg=service-account-issuer=https://homelab.pontifex.dev"
      "--kube-apiserver-arg=service-account-jwks-uri=https://homelab.pontifex.dev/openid/v1/jwks"
    ];
    disable = [
      #   "traefik"
      #   "servicelb"
      #   "local-storage"
    ];

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
            "accounts.gethomepage.enabled" = "false";
          };
          rbac = {
            "policy.default" = "role:readonly";
            "policy.csv" = ''
              p, gethomepage, role:readonly
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
  ];

  networking.firewall.allowedUDPPorts = lib.mkIf config.services.k3s.enable [
    8472 # Flannel VXLAN: required if using multi-node for inter-node networking
  ];

  environment.systemPackages = with pkgs; [
    kubectl
  ];
}
