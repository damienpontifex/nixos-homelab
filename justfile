# Container name for persistent Nix cache
dev_container_name := "nixos-homelab-dev"

# Display available commands and their descriptions
help:
    @just --list

# Remove the persistent Nix container (preserves volumes for nix store cache)
clean:
    docker compose down
    @echo "Container {{dev_container_name}} removed. Volumes preserved for caching. Next command will create a fresh container."

[group('dev')]
fmt: _ensure_dev_container
    docker exec {{dev_container_name}} nix fmt .

lint-unused: _ensure_container
    @echo "Checking for unused code with deadnix..."
    docker exec {{dev_container_name}} nix run nixpkgs#deadnix -- --exclude hardware-configuration.nix .

lint-statix: _ensure_container
    @echo "Checking for lint issues with statix..."
    docker exec {{dev_container_name}} nix run nixpkgs#statix -- check --ignore hardware-configuration.nix .

# Check for lint issues (unused arguments, dead code, etc.)
[group('dev')]
lint: lint-unused lint-statix

# Fix lint issues automatically
[group('dev')]
lint-fix: _ensure_container
    @echo "Checking for unused code with deadnix..."
    docker exec {{dev_container_name}} nix run nixpkgs#deadnix -- --edit .
    @echo "Fixing lint issues with statix..."
    docker exec {{dev_container_name}} nix run nixpkgs#statix -- fix .
    @echo "Formatting code..."
    docker exec {{dev_container_name}} nix fmt .

# Validate flake configuration for all systems (evaluation only)
[group('dev')]
validate: _ensure_container
    docker exec {{dev_container_name}} nix flake check --all-systems

# Validate and test-build all systems (slower but more thorough)
[group('dev')]
validate-build: _ensure_container
    docker exec {{dev_container_name}} nix flake check --all-systems
    @echo "Building homeserver configuration (dry-run)..."
    docker exec {{dev_container_name}} nix build .#nixosConfigurations.homeserver.config.system.build.toplevel --dry-run
    @echo "Building rpi-node-1 configuration (dry-run)..."
    docker exec {{dev_container_name}} nix build .#nixosConfigurations.rpi-node-1.config.system.build.toplevel --dry-run
    @echo "All validations passed!"

# Show flake outputs for all systems
[group('dev')]
show: _ensure_container
    docker exec {{dev_container_name}} nix flake show --all-systems

# Run interactive bash shell in Nix Docker container
[group('dev')]
interactive: _ensure_container
    docker exec -it {{dev_container_name}} bash

# Build ISO image using nix-community/nixos-generators
iso: _ensure_container
    docker exec {{dev_container_name}} nix run github:nix-community/nixos-generators -- --format iso --flake .#homeserver

# Build homeserver ISO and move to current directory
homeserver-iso: _ensure_container
    docker exec {{dev_container_name}} sh -c 'nix build .#homeserver && mv result/iso/nixos-*.iso .'

# Update flake inputs
[group('dev')]
update: _ensure_container
    docker exec {{dev_container_name}} nix flake update

# Rebuild NixOS system (assumed to be running on target machine)
[group('ops')]
rebuild HOSTNAME=`hostname`: _ensure_container
    nixos-rebuild switch --flake .#{{HOSTNAME}}

# Build VM for homeserver
build-vm: _ensure_container
    docker exec {{dev_container_name}} nixos-rebuild build-vm --flake .#homeserver

# Install NixOS to remote x86_64 machine
[group('install')]
install-homeserver HOST_IP: (install-machine "homeserver" HOST_IP)

[group('install')]
install-vm HOST_IP: (install-machine "vm" HOST_IP)

# Remember, will need to set `passwd` on remote machine
[group('install')]
install-machine HOSTNAME HOST_IP: _ensure_container
    #!/usr/bin/env bash
    set -euo pipefail
    set -x
    # So don't get errors from nix about unknown files
    git add .

    tempdir=$(mktemp -d)
    mkdir -p "$tempdir/var/lib/sops-nix/age"
    export public_key=$(age-keygen --output "$tempdir/var/lib/sops-nix/age/keys.txt" 2>&1 | awk '{print $3}')
    # Add the new public key to .sops.yaml
    yq -i '
      .keys += (strenv(public_key) | . anchor = "{{HOSTNAME}}") 
      | .creation_rules[0].key_groups[0].age += ((.keys[-1] | anchor) | . alias |= .)
    ' .sops.yaml
    # re-encrypt secrets.yaml with the new key
    sops updatekeys secrets.yaml

    # Make a temp director in the container and copy the new key in
    container_tmp_dir=$(docker exec {{dev_container_name}} mktemp -d)
    docker exec {{dev_container_name}} mkdir -p "$container_tmp_dir/var/lib/sops-nix/age"
    docker cp "$tempdir/var/lib/sops-nix/age/keys.txt" "{{dev_container_name}}:$container_tmp_dir/var/lib/sops-nix/age/keys.txt"

    docker exec -it {{dev_container_name}} \
      nix run github:numtide/nixos-anywhere -- \
        --extra-files "$container_tmp_dir" \
        --flake .#{{HOSTNAME}} nixos@{{HOST_IP}}

_reinstall-machine:
  tempdir=$(mktemp -d) && \
  mkdir -p "$tempdir/var/lib/sops-nix/age" && \
  cp /var/lib/sops-nix/age/keys.txt "$tempdir/var/lib/sops-nix/age/keys.txt" && \
  sudo nix --extra-experimental-features "nix-command flakes" \
    run github:numtide/nixos-anywhere -- \
    --extra-files "$tempdir" \
    --flake ".#$(hostname)" root@localhost

# Start NixOS upgrade on remote {{HOST}}
[group('ops')]
upgrade HOST="homeserver":
  ssh ponti@{{HOST}}.local 'sudo nixos-rebuild switch --flake github:damienpontifex/nixos-homelab#{{HOST}} --show-trace --no-update-lock-file --refresh --accept-flake-config'

# View NixOS upgrade logs on remote {{HOST}}
[group('ops')]
upgrade-logs HOST="homeserver.local":
  ssh ponti@{{HOST}} 'journalctl -fu nixos-upgrade.service'

# Build Raspberry Pi SD card image for rpi-node-1
rpi-image: _ensure_container
    docker exec {{dev_container_name}} sh -c 'nix build .#packages.aarch64-linux.rpi-node-1 && ls -lh result/sd-image/*.img'
    @echo ""
    @echo "SD card image built! To flash to SD card:"
    @echo "  1. Insert SD card and find device (diskutil list on macOS)"
    @echo "  2. Unmount: diskutil unmountDisk /dev/diskN"
    @echo "  3. Flash: sudo dd if=result/sd-image/*.img of=/dev/rdiskN bs=4M status=progress"
    @echo "  4. Eject: diskutil eject /dev/diskN"

# Check if container exists and is running, start it if stopped, create if it doesn't exist
_ensure_container:
    #!/usr/bin/env bash
    if docker ps --format '{{{{.Names}}' | grep -q "^{{dev_container_name}}$"; then
        # Container is running
        true
    elif docker ps -a --format '{{{{.Names}}' | grep -q "^{{dev_container_name}}$"; then
        # Container exists but is stopped
        echo "Starting existing container {{dev_container_name}}..."
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo '') docker compose up -d nix
    else
        # Container doesn't exist
        echo "Creating new container {{dev_container_name}}..."
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
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo '') docker compose up -d
    else
        # Container doesn't exist
        echo "Creating new dev container {{dev_container_name}}..."
        GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo '') docker compose up -d
        docker exec -it {{dev_container_name}} sh -c 'nix-channel --update'
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

