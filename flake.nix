{
  description = "Homelab NixOS + k3s";

  # Enable flakes for anyone building this flake (without system-wide flakes enabled)
  nixConfig = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { self, nixpkgs, nixos-generators, nixos-hardware, ... }: 
    let
      lib = nixpkgs.lib;
      # Helper function to generate ISOs from existing configs
      mkIso = hostName: cfg: nixos-generators.nixosGenerate {
        inherit (cfg.pkgs.stdenv.hostPlatform) system;
        # Automatically pull the modules defined in nixosConfigurations
        modules = cfg._module.args.modules;
        format = "iso";
      };

      # Filter configurations by architecture to put them in the right packages set
      hostsFor = system: lib.filterAttrs (_: cfg: cfg.pkgs.stdenv.hostPlatform.system == system) self.nixosConfigurations;
    in
    {
      # Import all host configurations from hosts/default.nix
      nixosConfigurations = import ./hosts { inherit nixpkgs nixos-hardware; };

      # Automatically generate ISOs for every host in nixosConfigurations
      packages = {
        x86_64-linux = lib.mapAttrs mkIso (hostsFor "x86_64-linux");
        aarch64-linux = lib.mapAttrs mkIso (hostsFor "aarch64-linux");
      };
    };
}
