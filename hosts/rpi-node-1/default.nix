{
  imports = [
    ./hardware.nix
    ../../modules  # Imports common modules from modules/default.nix
    ../../modules/k3s.nix  # K3s is optional, imported per-host
  ];

  networking.hostName = "rpi-node-1";

  services.k3s = {
    role = "agent";
    serverAddr = "https://homeserver.local:6443";
    # tokenFile will be added later via secrets
  };
}

