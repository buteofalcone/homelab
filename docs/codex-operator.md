# Codex operator account

`codex-ops` is an optional, dedicated SSH account for non-interactive homelab maintenance. It has no usable password and accepts one Ed25519 public key only from Tailscale source address ranges. SSH agent, TCP and X11 forwarding are disabled for that key.

The account intentionally has `NOPASSWD: ALL`. This means possession of its private key is equivalent to root access to the HP server. Keep that key only on the trusted administration PC, never commit it, and remove the account if that PC or key is compromised.

Provision it once from an existing administrator account:

```bash
cd /opt/homelab
sudo make provision-codex-operator KEY_FILE=/tmp/codex_ops_ed25519.pub
```

Verify from the administration PC:

```bash
ssh -i ~/.ssh/codex_ops_ed25519 codex-ops@hp-server 'sudo -n true && echo CODEX_SUDO_OK'
```

Standard `sudo` logging remains enabled. To revoke access, remove `/etc/sudoers.d/90-codex-ops` and the account with an existing administrator session:

```bash
sudo rm /etc/sudoers.d/90-codex-ops
sudo userdel --remove codex-ops
```

Generate a fresh key and rerun provisioning instead of copying an old private key to another computer.
