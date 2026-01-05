.SHELLFLAGS := -o errexit -o nounset -o pipefail 
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables 
MAKEFLAGS += --no-builtin-rules
.PHONY: all help build build-iso build-system validate check fmt format update clean write-to-usb

# Docker wrapper for Nix commands (macOS compatible)
NIX_DOCKER = docker run --rm \
	--env NIX_CONFIG="experimental-features = nix-command flakes"$$'\n'"access-tokens = github.com=$$(gh auth token 2>/dev/null || echo '')" \
	--volume "$$(pwd):/build" \
	--workdir /build \
	nixos/nix

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
	@$(NIX_DOCKER) sh -c " \
		nix flake check --all-systems 2>&1 || true && \
		echo '' && \
		echo 'Checking flake metadata...' && \
		nix flake metadata && \
		echo '' && \
		echo 'Evaluating ISO configuration...' && \
		nix eval .#nixosConfigurations.iso.config.system.name && \
		echo 'Evaluating system configuration...' && \
		nix eval .#nixosConfigurations.nixos-machine.config.system.name && \
		echo '' && \
		echo '✓ All configurations are valid!' \
	"

## check: Alias for validate
check: validate

## fmt: Format all Nix files with nixpkgs-fmt
fmt:
	@echo "Formatting Nix files..."
	@$(NIX_DOCKER) sh -c "nix-shell -p nixpkgs-fmt --run 'nixpkgs-fmt /build/*.nix'"
	@echo "✓ Formatting complete!"

## format: Alias for fmt
format: fmt

## build: Build ISO image (alias for build-iso)
build: build-iso

## build-iso: Build the ISO installer image
build-iso:
	@echo "Building ISO image..."
	@$(NIX_DOCKER) sh -c " \
		nix build .#iso -L && \
		cp -L result/iso/*.iso /build/nixos.iso \
	"
	@echo ""
	@echo "✓ ISO built successfully!"
	@ls -lh nixos.iso

## build-system: Build the system configuration (test without installing)
build-system:
	@echo "Building system configuration..."
	@$(NIX_DOCKER) nix build .#nixosConfigurations.nixos-machine.config.system.build.toplevel -L
	@echo ""
	@echo "✓ System configuration built successfully!"
	@ls -lh result

## update: Update flake lock file to latest dependencies
update:
	@echo "Updating flake inputs..."
	@$(NIX_DOCKER) sh -c " \
		nix flake update && \
		echo '' && \
		echo '✓ Flake updated! Review changes with: git diff flake.lock' \
	"

## clean: Remove build artifacts and result symlinks
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf result result.iso nixos.iso
	@echo "✓ Clean complete!"

## write-to-usb: Write ISO to USB drive (WARNING: destructive!)
write-to-usb:
	@echo "Available disks:"
	@diskutil list || lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null
	@echo ""
	@read -p "Enter the disk to write to (e.g., /dev/disk2 or /dev/sdb): " DISK; \
	echo ""; \
	echo "WARNING: This will erase all data on $$DISK"; \
	read -p "Are you sure? (type 'yes' to continue): " CONFIRM; \
	if [ "$$CONFIRM" = "yes" ]; then \
		if command -v diskutil >/dev/null 2>&1; then \
			diskutil unmountDisk $$DISK; \
			sudo dd if=nixos.iso of=$$DISK bs=4m status=progress; \
			diskutil eject $$DISK; \
		else \
			sudo dd if=nixos.iso of=$$DISK bs=4M status=progress oflag=sync; \
		fi; \
		echo "✓ USB drive written successfully!"; \
	else \
		echo "Cancelled."; \
	fi

## show-config: Show the full evaluated system configuration
show-config:
	@$(NIX_DOCKER) sh -c " \
		nix eval .#nixosConfigurations.nixos-machine.config --json | jq -r 'keys | .[]' | head -20 && \
		echo '...' && \
		echo '(Showing first 20 keys. Use make show-config-option OPTION=<key> to see specific values)' \
	"

## show-config-option: Show a specific configuration option value
show-config-option:
	@$(NIX_DOCKER) nix eval .#nixosConfigurations.nixos-machine.config.$(OPTION) --json | jq .

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
