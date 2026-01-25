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

  # Enable flakes on deployed systems (for local nixos-rebuild operations)
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.11";
}
