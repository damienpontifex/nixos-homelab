{
  description = "NixOS configuration with git-tracked updates";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Or pin to a specific release:
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs }: {
    # ISO image for initial installation
    nixosConfigurations.iso = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";  # Change to x86_64-linux for Intel/AMD
      modules = [
        ./iso.nix
      ];
    };

    # Main system configuration for the installed machine
    nixosConfigurations.nixos-machine = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";  # Change to x86_64-linux for Intel/AMD
      modules = [
        ./configuration.nix
      ];
    };

    # Make ISO available as a package
    packages.aarch64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;
    # For x86_64 systems, use:
    # packages.x86_64-linux.iso = self.nixosConfigurations.iso.config.system.build.isoImage;
  };
}
