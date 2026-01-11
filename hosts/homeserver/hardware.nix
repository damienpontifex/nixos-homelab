{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usbhid" "ums_realtek" "usb_storage" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # Disko will manage these filesystems
  # The manual fileSystems definitions are replaced by disko configuration
  disko.devices = {
    disk = {
      main = {
        # This will be overridden by disko-install at installation time with --disk main /dev/XXX
        # Common values:
        #   VMs (UTM/QEMU): /dev/vda or /dev/sda
        #   Physical hardware: /dev/disk/by-id/ata-YOUR-ACTUAL-DISK-ID
        # The device path here is just a placeholder
        device = "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # MBR partition for GRUB compatibility
            MBR = {
              type = "EF02";
              size = "1M";
              priority = 1; # Must be first partition
            };
            # EFI System Partition
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            # Root partition
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

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
