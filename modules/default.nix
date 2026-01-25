# Common modules imported by all hosts
{
  imports = [
    ./base.nix
    ./locale.nix
    ./users.nix
    ./networking.nix
    ./ssh.nix
    ./sops.nix
    ./maintenance.nix
  ];
}
