{ config, pkgs, ... }:

{
  users.users.ponti = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
    # For initial login, set a password with: mkpasswd -m sha-512
    # Or add your SSH key here:
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHJRaWQzblR+ygQf94y0DRS9OFCktOvxaXUVCTw51mib ponti@Damiens-MBP.localdomain" ];
    # For testing in VMs, you can set an initial password:
    # initialPassword = "changeme";
  };

  security.sudo.wheelNeedsPassword = false;
}
