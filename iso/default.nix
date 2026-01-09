{ modulesPath, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  networking.useDHCP = true;

  services.openssh.enable = true;

  systemd.services.autoinstall = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        nixos-install --flake github:damienpontifex/nixos-homelab#homeserver
        reboot
      '';
    };
  };
}
