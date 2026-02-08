{ lib, config, ... }:
{
  # Note: disko.nixosModules.disko should be imported at the host level
  # This module only configures disko, it doesn't import it

  options.diskConfig = {
    device = lib.mkOption {
      type = lib.types.str;
      description = "The device path for the main disk (e.g., /dev/sda or /dev/vda)";
    };

    useSwap = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use swap partition";
    };
  };

# Equivalent manual partitioning (with no swap)
# Partitioning (ESP first, then Root)
# parted /dev/sda -- mklabel gpt
# parted /dev/sda -- mkpart ESP fat32 1MB 513MB (This becomes /dev/sda1)
# parted /dev/sda -- set 1 esp on
# parted /dev/sda -- mkpart root ext4 513MB 100% (This becomes /dev/sda2)
# Formatting & Labeling
# mkfs.fat -F 32 -n boot /dev/sda1
# mkfs.ext4 -L nixos /dev/sda2
# Mounting with Security Flags
# mount /dev/disk/by-label/nixos /mnt
# mkdir -p /mnt/boot
# mount -o umask=0077 /dev/disk/by-label/boot /mnt/boot

  config = {
    disko.devices = {
      disk = {
        main = {
          device = config.diskConfig.device;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              # 512MiB boot partition at the start
              ESP = {
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ]; # So only the root user can read/write
                };
              };
              # Root partition filling the middle
              nixos = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            }
            # 8GB swap partition at the end (if configured)
            // lib.optionalAttrs config.diskConfig.useSwap {
              swap = {
                size = "8G"; # Default matching RAM
                content = {
                  type = "swap";
                  discardPolicy = "both";
                  resumeDevice = true; # Allows for hibernation support
                };
              };
            };
          };
        };
      };
    };
  };
}
