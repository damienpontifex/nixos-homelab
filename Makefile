.SHELLFLAGS := -o errexit -o nounset -o pipefail 
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables 
MAKEFLAGS += --no-builtin-rules
.PHONY: all help iso
.ONESHELL:

DOCKER_NIX := docker run --rm \
	-it \
	--env NIX_CONFIG="experimental-features = nix-command flakes"$$'\n'"access-tokens = github.com=$$(gh auth token 2>/dev/null || echo '')" \
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

iso-package:
	$(DOCKER_NIX) nix build .#iso

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

anywhere:
	$(DOCKER_NIX) nix run github:numtide/nixos-anywhere -- --flake .#homeserver root@yourhost
