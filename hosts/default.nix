# Centralized host configurations
{
  nixpkgs,
  nixos-hardware,
  disko,
  sops-nix,
  self ? null,
  ...
}@inputs:
let
  lib = nixpkgs.lib;
in
{
  homeserver = lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit self inputs; };
    modules = [
      ./homeserver
      disko.nixosModules.disko
      sops-nix.nixosModules.sops
    ];
  };

  rpi-node-1 = lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      ./rpi-node-1
      nixos-hardware.nixosModules.raspberry-pi-4
      sops-nix.nixosModules.sops
    ];
  };

  vm = lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit self sops-nix inputs; };
    modules = [
      ./vm
      disko.nixosModules.disko
      sops-nix.nixosModules.sops
    ];
  };
}
