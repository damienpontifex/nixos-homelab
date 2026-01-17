{
  # Note: sops-nix.nixosModules.sops should be imported at the host level
  # This module only configures sops, it doesn't import it

  sops = {
    defaultSopsFile = ../secrets.yaml;
    validateSopsFiles = false;

    age = {
      # For nixos-anywhere: Use SSH host key to derive age key
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      # Running nix in docker so mounted key is in the volume we map when running container
      keyFile = "/var/lib/sops-nix/age/keys.txt";
      generateKey = true;
    };
  };
}
