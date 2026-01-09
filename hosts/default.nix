# Centralized host configurations
{ nixpkgs, nixos-hardware, ... }:
let
  lib = nixpkgs.lib;
in
{
  homeserver = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./homeserver ];
  };

  rpi-node-1 = lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      ./rpi-node-1
      nixos-hardware.nixosModules.raspberry-pi-4
    ];
  };
}
