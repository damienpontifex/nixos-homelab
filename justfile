# Docker command for running Nix in a container (macOS compatible)
docker_nix := "docker run --rm --platform linux/amd64 -it \
--env NIX_CONFIG=\"experimental-features = nix-command flakes\"$'\\n'\"access-tokens = github.com=$(gh auth token 2>/dev/null || echo '')\"$'\\n'\"filter-syscalls = false\" \
--volume \"$(pwd):/build\" --workdir /build nixos/nix"

# Display available commands and their descriptions
help:
    @just --list

# Run interactive bash shell in Nix Docker container
interactive:
    {{docker_nix}} bash

# Build ISO image using nix-community/nixos-generators
iso:
    {{docker_nix}} sh -c 'nix run github:nix-community/nixos-generators -- --format iso --flake .#homeserver'

# Build homeserver ISO and move to current directory
homeserver-iso:
    {{docker_nix}} sh -c 'nix build .#homeserver && mv result/iso/nixos-*.iso .'

# Validate flake configuration for all systems
validate:
    {{docker_nix}} nix flake check --all-systems

# Show flake outputs for all systems
show:
    {{docker_nix}} nix flake show --all-systems

# Update flake inputs
update:
    {{docker_nix}} nix flake update

# Rebuild NixOS system for homeserver
rebuild:
    {{docker_nix}} nixos-rebuild switch --flake .#homeserver

# Build VM for homeserver
build-vm:
    {{docker_nix}} nixos-rebuild build-vm --flake .#homeserver

# Install NixOS to remote x86_64 machine
install-anywhere:
    # Boot from ISO
    # Connect to WiFi
    # Set root user password with `passwd`
    {{docker_nix}} sh -c "nix run github:numtide/nixos-anywhere -- --flake .#homeserver nixos@$HOST"

# Build Raspberry Pi SD card image for rpi-node-1
rpi-image:
    {{docker_nix}} sh -c 'nix build .#packages.aarch64-linux.rpi-node-1 && ls -lh result/sd-image/*.img'
    @echo ""
    @echo "SD card image built! To flash to SD card:"
    @echo "  1. Insert SD card and find device (diskutil list on macOS)"
    @echo "  2. Unmount: diskutil unmountDisk /dev/diskN"
    @echo "  3. Flash: sudo dd if=result/sd-image/*.img of=/dev/rdiskN bs=4M status=progress"
    @echo "  4. Eject: diskutil eject /dev/diskN"
