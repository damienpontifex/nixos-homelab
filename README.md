# NixOS Git-Tracked Configuration

This repository contains a NixOS configuration that tracks git as the source of truth, allowing you to build an ISO installer and then manage system updates through git.

## Repository Structure

- `flake.nix` - Flake configuration defining both ISO and system builds
- `iso.nix` - Configuration for the bootable ISO installer
- `configuration.nix` - Main system configuration for the installed machine
- `hardware-configuration.nix` - Generated during installation (not in git)
- `Makefile` - Helper commands for building, validating, and managing configurations
- `scripts/` - Helper scripts including git hooks

## Workflow

### 1. Build the ISO

Build the ISO image locally:

```bash
make build
```

Or using nix directly with flakes:

```bash
nix build .#iso
```

The ISO will be available as `result/iso/*.iso`

### 2. Write to USB and Boot

Write the ISO to a USB drive:

```bash
sudo dd if=nixos.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Boot from the USB drive.

### 3. Install NixOS from Git

After booting into the ISO, you have two options:

#### Option A: Use the helper script (recommended)

```bash
sudo /etc/nixos-install-from-git.sh
```

This interactive script will:
- Partition and format your disk
- Clone this repository to `/etc/nixos`
- Generate hardware configuration
- Install NixOS with your configuration

#### Option B: Manual installation

```bash
# 1. Partition and format your disk (example for /dev/sda)
parted /dev/sda -- mklabel gpt
parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/sda -- set 1 esp on
parted /dev/sda -- mkpart primary 512MiB 100%

mkfs.fat -F 32 -n boot /dev/sda1
mkfs.ext4 -L nixos /dev/sda2

# 2. Mount the partitions
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot

# 3. Clone this repository
git clone https://github.com/yourusername/nixos-build.git /mnt/etc/nixos

# 4. Generate hardware configuration
nixos-generate-config --root /mnt --no-filesystems

# 5. Update hostname in configuration.nix if needed
cd /mnt/etc/nixos
vim configuration.nix  # Change networking.hostName

# 6. Install NixOS
nixos-install --flake /mnt/etc/nixos#nixos-machine

# 7. Reboot
reboot
```

### 4. Push Repository to Git

Before you can pull updates, push this repository to GitHub/GitLab:

```bash
# On your development machine
git remote add origin https://github.com/yourusername/nixos-build.git
git push -u origin main
```

### 5. Update the Installed System

After installation, your system configuration lives in `/etc/nixos` and tracks your git repository.

To apply updates:

```bash
# Pull latest changes
cd /etc/nixos
git pull

# Rebuild the system
sudo nixos-rebuild switch --flake .#nixos-machine
```

### 6. Enable Automatic Updates (Optional)

Edit `/etc/nixos/configuration.nix` and uncomment the auto-upgrade section:

```nix
system.autoUpgrade = {
  enable = true;
  flake = "github:yourusername/nixos-build#nixos-machine";
  dates = "daily";
  allowReboot = false;
};
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake .#nixos-machine
```

## Making Changes

### Setup Git Hooks (Recommended)

Install the pre-commit hook to validate configurations before committing:

```bash
./scripts/install-hooks.sh
```

This will automatically run `make validate` before each commit to catch errors early.

### Local Development

1. Edit configuration files in this repository
2. Validate changes: `make validate`
3. Format Nix files: `make fmt`
4. Test the ISO build: `make build-iso`
5. Or test system build: `make build-system`
6. Commit and push changes

### On the Installed Machine

1. Make changes to files in `/etc/nixos`
2. Validate: `make validate`
3. Test the changes: `make test` or `sudo nixos-rebuild test --flake .#nixos-machine`
4. Apply permanently: `make switch` or `sudo nixos-rebuild switch --flake .#nixos-machine`
5. Commit and push: `git add -A && git commit -m "Update config" && git push`

## Makefile Commands

Run `make help` to see all available commands:

- `make validate` - Validate all Nix configurations (great for pre-commit hooks)
- `make fmt` - Format all Nix files with nixpkgs-fmt
- `make build-iso` - Build the ISO installer image
- `make build-system` - Build system configuration without installing
- `make update` - Update flake lock file to latest dependencies
- `make clean` - Remove build artifacts
- `make write-to-usb` - Interactive USB writer (safer than raw dd)
- `make show-config` - Show evaluated configuration options
- `make diff` - Show what would change (NixOS only)
- `make test` - Test configuration temporarily (NixOS only)
- `make switch` - Apply configuration permanently (NixOS only)

## Tips

- Use `make validate` before committing to catch configuration errors
- Use `make test` to try changes without making them permanent
- Use `make switch` to apply changes and make them the default boot option
- Use `nixos-rebuild boot` to apply changes for the next boot only
- Check system generations: `sudo nix-env --list-generations --profile /nix/var/nix/profiles/system`
- Rollback to previous generation: `sudo nixos-rebuild switch --rollback`
- Update dependencies periodically: `make update`

## Customization

- Update `configuration.nix` with your system settings
- Update `iso.nix` with tools you want available during installation
- Adjust the system architecture in `flake.nix` (aarch64-linux vs x86_64-linux)
- Set your timezone, locale, and hostname in `configuration.nix`
- Add your SSH public key in both `iso.nix` and `configuration.nix`
