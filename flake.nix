{
  description = "Homelab NixOS + k3s";

  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      nixos-hardware,
      disko,
      sops-nix,
      ...
    }@inputs:
    {
      # Import all host configurations from hosts/default.nix
      nixosConfigurations = import ./hosts {
        inherit
          self
          nixpkgs
          nixos-hardware
          disko
          sops-nix
          inputs
          ;
      };

      formatter = {
        x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
        x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin.nixfmt-tree;
        aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-tree;
      };

      # # Generate ISOs for x86_64 hosts and SD card images for aarch64 hosts (Raspberry Pi)
      # packages = {
      #   x86_64-linux = lib.mapAttrs (_: cfg: nixos-generators.nixosGenerate {
      #     inherit (cfg.pkgs.stdenv.hostPlatform) system;
      #     modules = cfg._module.args.modules;
      #     format = "iso";
      #   }) (hostsFor "x86_64-linux");
      #
      #   aarch64-linux = lib.mapAttrs (_: cfg: nixos-generators.nixosGenerate {
      #     inherit (cfg.pkgs.stdenv.hostPlatform) system;
      #     modules = cfg._module.args.modules;
      #     format = "sd-aarch64";
      #   }) (hostsFor "aarch64-linux");
      # };
    };

  # Enable flakes for anyone building this flake (without system-wide flakes enabled)
  nixConfig = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Private secrets repo. See ./docs/secretsmgmt.md
    # Authenticate via ssh and use shallow clone
    # mysecrets = {
    #   url = "https://github.com/damienpontifex/nix-secrets.git?ref=main&shallow=1";
    #   flake = false;
    # };
  };
}
