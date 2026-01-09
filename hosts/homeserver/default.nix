{
  imports = [
    ./hardware.nix
    ../../modules  # Imports common modules from modules/default.nix
    ../../modules/k3s.nix  # K3s is optional, imported per-host
  ];

  networking.hostName = "homeserver";
}
