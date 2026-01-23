{ pkgs, ... }:

{
  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    just
    neovim
  ];

  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font" ];
  };

  nixpkgs.config.allowUnfree = true;

  nix = {
    # Enable flakes on deployed systems (for local nixos-rebuild operations)
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };

    # systemctl status nix-optimise.(timer|service)
    optimise.automatic = true;

    # systemctl status nix-gc.(timer|service)
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  system.stateVersion = "25.11";
}
