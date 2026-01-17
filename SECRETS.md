# Secrets Management with sops-nix

This project uses [sops-nix](https://github.com/Mic92/sops-nix) for managing secrets, compatible with nixos-anywhere deployments.

## Prerequisites

Install sops and age:
```bash
nix-shell -p sops age
```

## Initial Setup

### 1. Generate Age Keys

For each host, you need to generate age keys from the SSH host keys. You have two options:

#### Option A: Using existing SSH host keys (recommended for nixos-anywhere)

If you already have the SSH host key for the target machine:
```bash
# Convert SSH host key to age key
nix-shell -p ssh-to-age --run "ssh-keyscan <hostname> | ssh-to-age"
# OR if you have the public key file
nix-shell -p ssh-to-age --run "cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age"
```

#### Option B: Generate age key manually

```bash
nix-shell -p age --run "age-keygen -o ~/.config/sops/age/keys.txt"
# Print the public key
age-keygen -y ~/.config/sops/age/keys.txt
```

### 2. Update .sops.yaml

Edit `.sops.yaml` and replace the placeholder age keys with your actual keys:

```yaml
keys:
  - &admin_ponti <YOUR_ADMIN_AGE_KEY>
  - &homeserver <HOMESERVER_AGE_KEY>
  - &rpi_node_1 <RPI_NODE_1_AGE_KEY>

creation_rules:
  - path_regex: secrets/[^/]+\.yaml$
    key_groups:
      - age:
          - *admin_ponti
          - *homeserver
          - *rpi_node_1
```

### 3. Create and Encrypt Secrets

Edit and encrypt the file:
```bash
sops edit secrets/secrets.yaml
```

### 4. Commit Encrypted Secrets

The encrypted file is safe to commit to git:
```bash
git add secrets/secrets.yaml .sops.yaml
git commit -m "Add encrypted WiFi credentials"
```

## Using with nixos-anywhere

The configuration is set up to work seamlessly with nixos-anywhere. The SSH host key on the target machine will be used to decrypt secrets during installation.

### Deploy with nixos-anywhere

```bash
# Deploy to a new machine
nixos-anywhere --flake .#rpi-node-1 root@<target-ip>
```

The deployment process:
1. nixos-anywhere installs NixOS on the target
2. The SSH host key is generated during installation
3. sops-nix derives the age key from the SSH host key
4. Secrets are decrypted using this age key
5. WiFi credentials are configured automatically

## How It Works

### Age Key Derivation

The system automatically derives age keys from SSH host keys at `/etc/ssh/ssh_host_ed25519_key`. This happens in `modules/sops.nix`:

```nix
sops.age = {
  sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  keyFile = "/var/lib/sops-nix/key.txt";
  generateKey = true;
};
```

### WiFi Configuration

In `modules/networking.nix`, the WiFi password is loaded from the encrypted secrets:

```nix
networking.wireless = {
  enable = true;
  networks = {
    PontiFi = {
      pskRaw = "ext:wifi_password";
    };
  };
  environmentFile = config.sops.secrets.wifi-credentials.path;
};
```

## Bootstrapping a New Machine

### Before Deployment

1. Get the SSH host key from the target machine (or generate one):
   ```bash
   # If the machine already exists
   ssh-keyscan <target-ip> | ssh-to-age
   
   # Or generate a new key pair locally for pre-configuration
   ssh-keygen -t ed25519 -f ./host_key -N ""
   cat host_key.pub | ssh-to-age
   ```

2. Add the age key to `.sops.yaml`

3. Re-encrypt secrets with the new key:
   ```bash
   sops updatekeys secrets/secrets.enc.yaml
   ```

### During Deployment

When using nixos-anywhere, the system will:
1. Generate SSH host keys during installation
2. Automatically derive age keys from those SSH host keys
3. Decrypt secrets using the derived keys
4. Configure WiFi with the decrypted password

### After Deployment

If you need to rotate secrets or add new hosts:
```bash
# Edit encrypted file
sops secrets/secrets.enc.yaml

# Update all keys (after adding new hosts to .sops.yaml)
sops updatekeys secrets/secrets.enc.yaml
```

## Adding More Secrets

To add additional secrets (like k3s tokens):

1. Edit the encrypted file:
   ```bash
   sops secrets/secrets.enc.yaml
   ```

2. Add the new secret:
   ```yaml
   wifi_password: your_wifi_password
   k3s_token: your_k3s_token
   ```

3. Configure sops to expose the secret in `modules/sops.nix`:
   ```nix
   secrets = {
     wifi-credentials = { ... };
     k3s-token = {
       mode = "0440";
       owner = config.users.users.root.name;
     };
   };
   ```

4. Reference it in your configuration:
   ```nix
   services.k3s.tokenFile = config.sops.secrets.k3s-token.path;
   ```

## Troubleshooting

### Secrets not decrypting

Check that the age key is properly derived:
```bash
# On the target machine
cat /var/lib/sops-nix/key.txt
```

### Permission errors

Ensure the secret has correct ownership in `modules/sops.nix`:
```nix
secrets.wifi-credentials = {
  mode = "0440";
  owner = config.users.users.root.name;
  group = config.users.groups.root.name;
};
```

### Re-encrypting after key changes

```bash
sops updatekeys secrets/secrets.enc.yaml
```
