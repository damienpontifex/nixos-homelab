{ config, pkgs, ... }:

{
  # Decrypt user password to /run/secrets-for-users so it can be used to create the user
  sops.secrets.pontiUserPassword.neededForUsers = true;
  users.mutableUsers = false; # Required for password to be set via sops during system activation

  users.users = {
    ponti = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets.pontiUserPassword.path;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      packages = with pkgs; [ ];
      # For initial login, set a password with: mkpasswd -m sha-512
      # Or add your SSH key here:
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHJRaWQzblR+ygQf94y0DRS9OFCktOvxaXUVCTw51mib ponti@Damiens-MBP.localdomain"
      ];
    };
  };

  security.sudo.wheelNeedsPassword = false;
}
