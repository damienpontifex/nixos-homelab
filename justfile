# Container name for persistent Nix cache
container_name := "nixos-homelab-builder"
dev_container_name := "nixos-homelab-dev"

# Display available commands and their descriptions
help:
    @just --list

# Remove the persistent Nix container (preserves volumes for nix store cache)
clean:
    docker compose down
    @echo "Container {{container_name}} removed. Volumes preserved for caching. Next command will create a fresh container."

[group('dev')]
fmt: _ensure_dev_container
    docker exec {{dev_container_name}} nix fmt .

lint-unused: _ensure_container
    @echo "Checking for unused code with deadnix..."
    docker exec {{container_name}} nix run nixpkgs#deadnix -- --exclude hardware-configuration.nix .

lint-statix: _ensure_container
    @echo "Checking for lint issues with statix..."
    docker exec {{container_name}} nix run nixpkgs#statix -- check --ignore hardware-configuration.nix .

# Check for lint issues (unused arguments, dead code, etc.)
[group('dev')]
lint: lint-unused lint-statix

# Fix lint issues automatically
[group('dev')]
lint-fix: _ensure_container
    @echo "Checking for unused code with deadnix..."
    docker exec {{container_name}} nix run nixpkgs#deadnix -- --edit .
    @echo "Fixing lint issues with statix..."
    docker exec {{container_name}} nix run nixpkgs#statix -- fix .
    @echo "Formatting code..."
    docker exec {{container_name}} nix fmt .

# Validate flake configuration for all systems (evaluation only)
[group('dev')]
validate: _ensure_container
    docker exec {{container_name}} nix flake check --all-systems

# Validate and test-build all systems (slower but more thorough)
[group('dev')]
validate-build: _ensure_container
    docker exec {{container_name}} nix flake check --all-systems
    @echo "Building homeserver configuration (dry-run)..."
    docker exec {{container_name}} nix build .#nixosConfigurations.homeserver.config.system.build.toplevel --dry-run
    @echo "Building rpi-node-1 configuration (dry-run)..."
    docker exec {{container_name}} nix build .#nixosConfigurations.rpi-node-1.config.system.build.toplevel --dry-run
    @echo "All validations passed!"

# Show flake outputs for all systems
[group('dev')]
show: _ensure_container
    docker exec {{container_name}} nix flake show --all-systems

# Run interactive bash shell in Nix Docker container
[group('dev')]
interactive: _ensure_container
    docker exec -it {{container_name}} bash

# Build ISO image using nix-community/nixos-generators
iso: _ensure_container
    docker exec {{container_name}} sh -c 'nix run github:nix-community/nixos-generators -- --format iso --flake .#homeserver'

# Build homeserver ISO and move to current directory
homeserver-iso: _ensure_container
    docker exec {{container_name}} sh -c 'nix build .#homeserver && mv result/iso/nixos-*.iso .'

# Update flake inputs
[group('dev')]
update: _ensure_container
    docker exec {{container_name}} nix flake update

# Rebuild NixOS system (assumed to be running on target machine)
[group('ops')]
rebuild HOSTNAME=`hostname`: _ensure_container
    nixos-rebuild switch --flake .#{{HOSTNAME}}

# Build VM for homeserver
build-vm: _ensure_container
    docker exec {{container_name}} nixos-rebuild build-vm --flake .#homeserver

# Install NixOS to remote x86_64 machine
[group('install')]
install-homeserver HOST_IP: (install-machine "homeserver" HOST_IP)

[group('install')]
install-vm HOST_IP: (install-machine "vm" HOST_IP)

[group('install')]
install-machine HOSTNAME HOST_IP: _ensure_container
    #!/usr/bin/env bash
    # So don't get errors from nix about unknown files
    git add .

    docker exec -it {{container_name}} sh -c '
      tempdir=$(mktemp -d)
      cleanup() {
        rm -rf "$tempdir"
      }
      trap cleanup EXIT

      mkdir -p "$tempdir/var/lib/sops-nix/age"
      echo "$(tail -1 /var/lib/sops-nix/age/keys.txt)" > "$tempdir/var/lib/sops-nix/age/keys.txt"

      nix run github:numtide/nixos-anywhere -- \
        --extra-files "$tempdir" \
        --flake .#{{HOSTNAME}} nixos@{{HOST_IP}} \
        --generate-hardware-config nixos-generate-config ./hosts/{{HOSTNAME}}/hardware-configuration.nix
    '

# Start NixOS upgrade on remote {{HOST}}
[group('ops')]
upgrade HOST="homeserver.local":
  ssh ponti@{{HOST}} 'sudo systemctl start nixos-upgrade'

# View NixOS upgrade logs on remote {{HOST}}
[group('ops')]
upgrade-logs HOST="homeserver.local":
  ssh ponti@{{HOST}} 'journalctl -xeu nixos-upgrade.service'

[group('ops')]
homelab-kubeconfig:
  #!/usr/bin/env bash
  set -euo pipefail
  
  # Backup current config
  cp ~/.kube/config ~/.kube/config.backup
  
  # Remove any existing homelab entries from current config
  kubectl config delete-context homelab 2>/dev/null || true
  kubectl config delete-cluster homelab 2>/dev/null || true
  kubectl config delete-user homelab 2>/dev/null || true
  
  # Get k3s config from homeserver
  ssh ponti@homeserver.local 'sudo k3s kubectl config view --raw' > /tmp/homelab-k3s-config.yaml
  
  # Rename cluster, user, context and fix server address
  sed -i.bak \
    -e 's/name: default$/name: homelab/g' \
    -e 's/cluster: default$/cluster: homelab/g' \
    -e 's/user: default$/user: homelab/g' \
    -e 's|https://127.0.0.1:|https://homeserver.local:|g' \
    /tmp/homelab-k3s-config.yaml
  
  # Merge with existing config
  KUBECONFIG=~/.kube/config:/tmp/homelab-k3s-config.yaml kubectl config view --flatten > ~/.kube/config.new
  mv ~/.kube/config.new ~/.kube/config
  
  # Clean up
  rm /tmp/homelab-k3s-config.yaml /tmp/homelab-k3s-config.yaml.bak
  
  echo "Successfully merged homelab kubeconfig. Backup saved at ~/.kube/config.backup"

# Build Raspberry Pi SD card image for rpi-node-1
rpi-image: _ensure_container
    docker exec {{container_name}} sh -c 'nix build .#packages.aarch64-linux.rpi-node-1 && ls -lh result/sd-image/*.img'
    @echo ""
    @echo "SD card image built! To flash to SD card:"
    @echo "  1. Insert SD card and find device (diskutil list on macOS)"
    @echo "  2. Unmount: diskutil unmountDisk /dev/diskN"
    @echo "  3. Flash: sudo dd if=result/sd-image/*.img of=/dev/rdiskN bs=4M status=progress"
    @echo "  4. Eject: diskutil eject /dev/diskN"

# Check if container exists and is running, start it if stopped, create if it doesn't exist
_ensure_container:
    #!/usr/bin/env bash
    if docker ps --format '{{{{.Names}}' | grep -q "^{{container_name}}$"; then
        # Container is running
        true
    elif docker ps -a --format '{{{{.Names}}' | grep -q "^{{container_name}}$"; then
        # Container exists but is stopped
        echo "Starting existing container {{container_name}}..."
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo '') docker compose up -d nix
    else
        # Container doesn't exist
        echo "Creating new container {{container_name}}..."
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo '') docker compose up -d nix
    fi

# Check if dev container exists and is running, start it if stopped, create if it doesn't exist
_ensure_dev_container:
    #!/usr/bin/env bash
    if docker ps --format '{{{{.Names}}' | grep -q "^{{dev_container_name}}$"; then
        # Container is running
        true
    elif docker ps -a --format '{{{{.Names}}' | grep -q "^{{dev_container_name}}$"; then
        # Container exists but is stopped
        echo "Starting existing dev container {{dev_container_name}}..."
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo '') docker compose up -d nix-dev
    else
        # Container doesn't exist
        echo "Creating new dev container {{dev_container_name}}..."
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo '') docker compose up -d nix-dev
    fi


tunnel:
  #!/usr/bin/env bash
  set -uox pipefail
  [ -f ~/.cloudflared/cert.pem ] || cloudflared tunnel login
  TUNNEL=$(cloudflared tunnel list --name cf-demo-2 --output json | tee /dev/tty | jq '.[0]' --exit-status)
  if [ $? -ne 0 ]; then
    TUNNEL=$(cloudflared tunnel create --output json cf-demo-2 | tee /dev/tty)
  fi
  TUNNEL_ID=$(jq --raw-output '.id' <<< "$TUNNEL")
  cloudflared tunnel route dns --overwrite-dns "$TUNNEL_ID" cf-demo-2.pontifex.dev
  export TUNNEL_ID
  envsubst < ~/.cloudflared/cf-demo-1.yml | tee ~/.cloudflared/$TUNNEL_ID.yml
  cloudflared tunnel --config "$HOME/.cloudflared/$TUNNEL_ID.yml" run "$TUNNEL_ID"

