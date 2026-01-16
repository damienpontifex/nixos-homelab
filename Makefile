.SHELLFLAGS := -o errexit -o nounset -o pipefail 
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables 
MAKEFLAGS += --no-builtin-rules
.PHONY: all help iso
.ONESHELL:

DOCKER_NIX := docker run --rm \
	--platform linux/amd64 \
	-it \
	--env NIX_CONFIG="experimental-features = nix-command flakes"$$'\n'"access-tokens = github.com=$$(gh auth token 2>/dev/null || echo '')"$$'\n'"filter-syscalls = false" \
	--volume "$$(pwd):/build" \
	--workdir /build \
	nixos/nix \
	$(1)

# Shell function to run Nix commands in Docker (macOS compatible)
# Usage: nix_docker "nix flake check"
define nix_docker_sh
	$(call nix_docker, "sh -c '$(1)'")
endef

## help: Display available commands and their descriptions
help:
	@echo "Usage:"
	@sed -n 's/^##//p' $(MAKEFILE_LIST) \
		| sort \
		| awk -v bold="$$(tput bold)" -v normal="$$(tput sgr0)" '{ $$1 = bold $$1 normal; print }' \
		| column -t -s ':'

interactive:
	$(DOCKER_NIX) bash

iso:
	$(DOCKER_NIX) sh -c 'nix run github:nix-community/nixos-generators -- --format iso --flake .#homeserver'

homeserver-iso:
	$(DOCKER_NIX) sh -c 'nix build .#homeserver && mv result/iso/nixos-*.iso .'

validate:
	$(DOCKER_NIX) nix flake check --all-systems

show:
	$(DOCKER_NIX) nix flake show --all-systems

update:
	$(DOCKER_NIX) nix flake update

rebuild:
	$(DOCKER_NIX) nixos-rebuild switch --flake .#homeserver

build-vm:
	$(DOCKER_NIX) nixos-rebuild build-vm --flake .#homeserver

## install-anywhere: Install NixOS to remote x86_64 machine
install-anywhere:
	# Boot from ISO
	# Connect to WiFi
	# Set root user password with `passwd`
	$(call DOCKER_NIX, sh -c "nix run github:numtide/nixos-anywhere -- --flake .#homeserver nixos@$$HOST")

## rpi-image: Build Raspberry Pi SD card image for rpi-node-1
rpi-image:
	$(call DOCKER_NIX, sh -c 'nix build .#packages.aarch64-linux.rpi-node-1 && ls -lh result/sd-image/*.img')
	@echo ""
	@echo "SD card image built! To flash to SD card:"
	@echo "  1. Insert SD card and find device (diskutil list on macOS)"
	@echo "  2. Unmount: diskutil unmountDisk /dev/diskN"
	@echo "  3. Flash: sudo dd if=result/sd-image/*.img of=/dev/rdiskN bs=4M status=progress"
	@echo "  4. Eject: diskutil eject /dev/diskN"
