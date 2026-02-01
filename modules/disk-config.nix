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

  config = {
    disko.devices = {
      disk = {
        main = {
          device = config.diskConfig.device;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
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
            } // lib.optionalAttrs config.diskConfig.useSwap {
              swap = {
                size = "8G"; # Default matching RAM
                content = {
                  type = "swap";
                  discardPolicy = "both";
                  resumeDevice = true; # Allows for hibernation support
                };
              };
            } // {
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
    };
  };
}
