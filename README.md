# NixOS Homelab

Mainly learning for now

#[Renovate panel](https://developer.mend.io/github/damienpontifex/nixos-homelab)

## Bootable USB from macOS
```bash
diskutil list
diskutil unmountDisk /dev/diskN  # replace N with your disk number
sudo dd bs=1M status=progress oflag=sync \
  if=$HOME/Downloads/nixos-minimal-25.11.3202.30a3c519afcf-x86_64-linux.iso \ # Or other appropriate ISO path
  of=/dev/rdiskN # replace N with your disk number
diskutil eject /dev/diskN  # replace N with your disk number
```

On the target machine, boot from the USB drive and run:
```bash
# Ensure secure boot is disabled in BIOS if applicable
# Set a root user password
passwd
# Connect to WiFi if needed
nmcli device wifi connect "<SSID>" password "<PASSWORD>"
ip addr show  # to find your IP address
```

On your local machine, run:
```bash
just install-anywhere <ip-address-of-target-machine>
```

