.SHELLFLAGS := -o errexit -o nounset -o pipefail 
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables 
MAKEFLAGS += --no-builtin-rules
.PHONY: all help build build-iso build-system validate check fmt format update clean write-to-usb

## help: Display available commands and their descriptions
help:
	@echo "Usage:"
	@sed -n 's/^##//p' $(MAKEFILE_LIST) \
		| sort \
		| awk -v bold="$$(tput bold)" -v normal="$$(tput sgr0)" '{ $$1 = bold $$1 normal; print }' \
		| column -t -s ':'

## validate: Validate all Nix configurations (runs on pre-commit)
validate:
	@echo "Validating flake..."
	@nix flake check --all-systems 2>&1 || true
	@echo ""
	@echo "Checking flake metadata..."
	@nix flake metadata
	@echo ""
	@echo "Evaluating ISO configuration..."
	@nix eval .#nixosConfigurations.iso.config.system.name --quiet
	@echo "Evaluating system configuration..."
	@nix eval .#nixosConfigurations.nixos-machine.config.system.name --quiet
	@echo ""
	@echo "✓ All configurations are valid!"

## check: Alias for validate
check: validate

## fmt: Format all Nix files with nixpkgs-fmt
fmt:
	@echo "Formatting Nix files..."
	@nix-shell -p nixpkgs-fmt --run "nixpkgs-fmt *.nix"
	@echo "✓ Formatting complete!"

## format: Alias for fmt
format: fmt

## build: Build ISO image (legacy - use build-iso)
build: build-iso

## build-iso: Build the ISO installer image
build-iso:
	@echo "Building ISO image..."
	@nix build .#iso -L
	@if [ -L result ]; then \
		cp -L result/iso/*.iso nixos.iso 2>/dev/null || true; \
		echo ""; \
		echo "✓ ISO built successfully!"; \
		ls -lh nixos.iso 2>/dev/null || ls -lh result/iso/*.iso; \
	fi

## build-iso-docker: Build ISO using Docker (for non-NixOS systems)
build-iso-docker:
	docker run --rm \
		--env NIX_CONFIG="experimental-features = nix-command flakes"$$'\n'"access-tokens = github.com=$$(gh auth token)" \
		--volume "$$(pwd):/build" \
		--workdir /build \
		nixos/nix \
		sh -c " \
			nix build .#iso -L && \
			cp -L result/iso/*.iso /build/nixos.iso \
		"

## build-system: Build the system configuration (test without installing)
build-system:
	@echo "Building system configuration..."
	@nix build .#nixosConfigurations.nixos-machine.config.system.build.toplevel -L
	@echo ""
	@echo "✓ System configuration built successfully!"
	@ls -lh result

## update: Update flake lock file to latest dependencies
update:
	@echo "Updating flake inputs..."
	@nix flake update
	@echo ""
	@echo "✓ Flake updated! Review changes with: git diff flake.lock"

## clean: Remove build artifacts and result symlinks
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf result result.iso nixos.iso
	@echo "✓ Clean complete!"

## write-to-usb: Write ISO to USB drive (WARNING: destructive!)
write-to-usb:
	@echo "Available disks:"
	@lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null || diskutil list
	@echo ""
	@read -p "Enter the disk to write to (e.g., /dev/sdb or /dev/disk2): " DISK; \
	echo ""; \
	echo "WARNING: This will erase all data on $$DISK"; \
	read -p "Are you sure? (type 'yes' to continue): " CONFIRM; \
	if [ "$$CONFIRM" = "yes" ]; then \
		sudo dd if=nixos.iso of=$$DISK bs=4M status=progress oflag=sync; \
		echo "✓ USB drive written successfully!"; \
	else \
		echo "Cancelled."; \
	fi

## show-config: Show the full evaluated system configuration
show-config:
	@nix eval .#nixosConfigurations.nixos-machine.config --json | jq -r 'keys | .[]' | head -20
	@echo "..."
	@echo "(Showing first 20 keys. Use 'nix eval .#nixosConfigurations.nixos-machine.config.OPTION' to see specific values)"

## diff: Show what would change with current config (requires NixOS)
diff:
	@echo "Comparing current system with new configuration..."
	@nixos-rebuild build --flake .#nixos-machine
	@nix store diff-closures /run/current-system ./result

## test: Test the configuration on current system (requires NixOS)
test:
	@echo "Testing configuration (temporary, will revert on reboot)..."
	@sudo nixos-rebuild test --flake .#nixos-machine

## switch: Apply configuration to current system (requires NixOS)
switch:
	@echo "Applying configuration..."
	@sudo nixos-rebuild switch --flake .#nixos-machine
