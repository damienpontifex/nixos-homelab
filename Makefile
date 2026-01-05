.SHELLFLAGS := -o errexit -o nounset -o pipefail 
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables 
MAKEFLAGS += --no-builtin-rules
.PHONY: all help build write-to-usb

## help: Display available commands and their descriptions
help:
	@echo "Usage:"
	@sed -n 's/^##//p' $(MAKEFILE_LIST) \
		| sort \
		| awk -v bold="$$(tput bold)" -v normal="$$(tput sgr0)" '{ $$1 = bold $$1 normal; print }' \
		| column -t -s ':'

build:
	docker run --rm \
		--env NIX_CONFIG="experimental-features = nix-command flakes"$$'\n'"access-tokens = github.com=$$(gh auth token)" \
		--volume "$$(pwd):/build" \
		--workdir /build \
		nixos/nix \
		sh -c " \
			nix-channel --update && \
			nix run github:nix-community/nixos-generators -- \
				--format iso \
				--configuration ./iso.nix \
				-o result.iso && \
			cp -L result.iso /build/nixos.iso \
		"

write-to-usb:
	sudo dd if=nixos.iso of=/dev/sdX bs=4M status=progress oflag=sync
