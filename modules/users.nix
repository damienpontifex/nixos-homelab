{ config, pkgs, ... }:

{
  users.users.ponti = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
  };

  security.sudo.wheelNeedsPassword = false;
}
