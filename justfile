# Container name for persistent Nix cache
container_name := "nixos-homelab-builder"

# Check if container exists and is running, start it if stopped, create if it doesn't exist
_ensure_container:
    #!/usr/bin/env bash
    if docker ps -a --format '{{{{.Names}}' | grep -q "^{{container_name}}$"; then
        if ! docker ps --format '{{{{.Names}}' | grep -q "^{{container_name}}$"; then
            echo "Starting existing container {{container_name}}..."
            docker start {{container_name}} > /dev/null
        fi
    else
        echo "Creating new container {{container_name}}..."
        docker run -d --platform linux/amd64 \
            --name {{container_name}} \
            --env NIX_CONFIG="experimental-features = nix-command flakes"$'\n'"access-tokens = github.com=$(gh auth token 2>/dev/null || echo '')"$'\n'"filter-syscalls = false" \
            --volume "$(pwd):/build" \
            --volume "$HOME/.config/sops:/var/lib/sops-nix:ro" \
            --workdir /build \
            nixos/nix sleep infinity
    fi

# Display available commands and their descriptions
help:
    @just --list

# Remove the persistent Nix container (clears cache)
clean-container:
    docker rm -f {{container_name}} || true
    @echo "Container {{container_name}} removed. Next command will create a fresh container."

fmt: _ensure_container
    docker exec {{container_name}} nix fmt .

# Run interactive bash shell in Nix Docker container
interactive: _ensure_container
    docker exec -it {{container_name}} bash

# Build ISO image using nix-community/nixos-generators
iso: _ensure_container
    docker exec {{container_name}} sh -c 'nix run github:nix-community/nixos-generators -- --format iso --flake .#homeserver'

# Build homeserver ISO and move to current directory
homeserver-iso: _ensure_container
    docker exec {{container_name}} sh -c 'nix build .#homeserver && mv result/iso/nixos-*.iso .'

# Validate flake configuration for all systems (evaluation only)
validate: _ensure_container
    docker exec {{container_name}} nix flake check --all-systems

# Validate and test-build all systems (slower but more thorough)
validate-build: _ensure_container
    docker exec {{container_name}} nix flake check --all-systems
    @echo "Building homeserver configuration (dry-run)..."
    docker exec {{container_name}} nix build .#nixosConfigurations.homeserver.config.system.build.toplevel --dry-run
    @echo "Building rpi-node-1 configuration (dry-run)..."
    docker exec {{container_name}} nix build .#nixosConfigurations.rpi-node-1.config.system.build.toplevel --dry-run
    @echo "All validations passed!"

# Show flake outputs for all systems
show: _ensure_container
    docker exec {{container_name}} nix flake show --all-systems

# Update flake inputs
update: _ensure_container
    docker exec {{container_name}} nix flake update

# Rebuild NixOS system for homeserver
rebuild: _ensure_container
    docker exec {{container_name}} nixos-rebuild switch --flake .#homeserver

# Build VM for homeserver
build-vm: _ensure_container
    docker exec {{container_name}} nixos-rebuild build-vm --flake .#homeserver

# Install NixOS to remote x86_64 machine
[group('install')]
install-anywhere HOST_IP: _ensure_container
    # Boot from ISO
    # Connect to WiFi
    # Set root user password with `passwd`
    # Needs interactive prompt when asking for password and others `--interactive --tty`
    docker exec -it {{container_name}} nix run github:numtide/nixos-anywhere -- --flake .#homeserver nixos@{{HOST_IP}}

[group('install')]
install-vm HOST_IP: _ensure_container
    #!/usr/bin/env bash
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
        --flake .#vm nixos@{{HOST_IP}} \
        --generate-hardware-config nixos-generate-config ./hosts/vm/hardware-configuration.nix
    '

# Build Raspberry Pi SD card image for rpi-node-1
rpi-image: _ensure_container
    docker exec {{container_name}} sh -c 'nix build .#packages.aarch64-linux.rpi-node-1 && ls -lh result/sd-image/*.img'
    @echo ""
    @echo "SD card image built! To flash to SD card:"
    @echo "  1. Insert SD card and find device (diskutil list on macOS)"
    @echo "  2. Unmount: diskutil unmountDisk /dev/diskN"
    @echo "  3. Flash: sudo dd if=result/sd-image/*.img of=/dev/rdiskN bs=4M status=progress"
    @echo "  4. Eject: diskutil eject /dev/diskN"
