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
  sops = {
    secrets = {
      k3s-token = lib.mkIf config.services.k3s.enable {
        sopsFile = ../secrets.yaml;
      };

      cloudflare-token = lib.mkIf config.services.k3s.enable {
        sopsFile = ../secrets.yaml;
      };
    };

    # Create a template for the cloudflare token secret
    templates."cloudflare-token-secret.yaml" = lib.mkIf config.services.k3s.enable {
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
    8472 # k3s: flannel: required if using multi-node for intern-node networking, also used for Cilium VXLAN
    4240 # Cilium health check
  ];

  # Allow metrics-server access to port 10250
  # These interfaces reflect the k3s networking interfaces
  networking.firewall.interfaces.cni0.allowedTCPPorts = [ 10250 ];
  networking.firewall.interfaces.flannel1.allowedTCPPorts = [ 10250 ];

  systemd.tmpfiles.rules = [
    "f+ /var/lib/rancher/k3s/server/audit.yaml 1777 root root - ${builtins.toFile "audit.yaml" ''
      apiVersion: audit.k8s.io/v1
      kind: Policy
      rules:
      - level: Metadata
    ''}"
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
      # Entra OIDC for api server
      "--kube-apiserver-arg=oidc-issuer-url=https://sts.windows.net/ff2b9041-8733-4fbd-a4e6-23f30567c4a4/"
      "--kube-apiserver-arg=oidc-client-id=f4a70612-f4fa-4f68-818c-5db39de8187d"
      "--kube-apiserver-arg=oidc-username-claim=unique_name"
      "--kube-apiserver-arg=oidc-groups-claim=roles"
      # Cilium
      "--flannel-backend=none" # Disable Flannel to use Cilium
      "--disable-kube-proxy" # Let Cilium handle kube-proxy functionality
      "--disable-network-policy" # Let Cilium handle network policies
      # Audit logging
      # "--kube-apiserver-arg=enable-admission-plugins=NodeRestriction,EventRateLimit"
      # "--kube-apiserver-arg=audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log"
      # "--kube-apiserver-arg=audit-policy-file=/var/lib/rancher/k3s/server/audit.yaml"
      # "--kube-apiserver-arg=audit-log-maxage=30"
      # "--kube-apiserver-arg=audit-log-maxbackup=10"
      # "--kube-apiserver-arg=audit-log-maxsize=100"
    ];
    disable = [
      # "traefik"
      # "servicelb"
      # "local-storage"
    ];
    gracefulNodeShutdown.enable = true;

    autoDeployCharts.cilium = lib.mkIf (config.services.k3s.role == "server") {
      name = "cilium";
      # https://artifacthub.io/packages/helm/cilium/cilium
      repo = "https://helm.cilium.io/";
      # renovate: datasource=helm registryUrl=https://helm.cilium.io depName=cilium
      version = "1.19.1";
      hash = "sha256-Uw7b6RnncNLlYcDZQ7An9wjdbH4EGsskGpIJ5G4HMVs=";
      targetNamespace = "kube-system";
      createNamespace = false; # kube-system already exists
      values = ./k3s-bootstrap/cilium-helm-values.yaml;
      # Enable bootstrap mode to install Cilium before the Kubernetes API is fully available
      # This is equivalent to what staticContentPort does in the nixpkgs k3s module
      extraFieldDefinitions = {
        spec.bootstrap = true;
      };
    };

    autoDeployCharts.argocd = lib.mkIf (config.services.k3s.role == "server") {
      name = "argocd";
      # https://artifacthub.io/packages/helm/argo-cd-oci/argo-cd
      repo = "oci://ghcr.io/argoproj/argo-helm/argo-cd";
      # renovate: datasource=helm registryUrl=https://argoproj.github.io/argo-helm depName=argo-cd
      version = "9.3.4";
      hash = "sha256-dpTJFsJgs8rZU3ejxgyggLSpeYGGZnFTPLeQVMV0wG0=";
      targetNamespace = "argocd";
      createNamespace = true;
      values = ./k3s-bootstrap/argocd-helm-values.yaml;
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
