{
  config,
  lib,
  sops-nix,
  inputs,
  ...
}:
{
  imports = [
    sops-nix.nixosModules.sops
  ];

  sops.defaultSopsFile = ../secrets.yaml;
  sops.validateSopsFiles = false;

  sops.age = {
    # For nixos-anywhere: Use SSH host key to derive age key
    sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    # Running nix in docker so mounted key is in the volume we map when running container
    keyFile = "/var/lib/sops-nix/age/keys.txt";
    generateKey = true;
  };
}
