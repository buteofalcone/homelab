# Homelab Agent Rules

## Scope

- Manage one Ubuntu server with Docker Engine and Docker Compose.
- Repository: `/opt/homelab` on host `hp-server`.
- Primary operator: `butenko`.
- Persistent application state: `/srv/appdata`.
- Persistent user data: `/srv/storage`.
- Use Docker Compose only. Do not introduce Kubernetes, Docker Swarm, Ansible, or Terraform.

## Remote workflow

- From SilverBrick, connect with `ssh hp-server`.
- Run repository commands from `/opt/homelab`.
- Prefer small, reviewable changes and report every command that changes host or service state.
- Do not assume the project folder on SilverBrick is a clone of `/opt/homelab`.

## Mandatory checks before changes

Run and review:

```bash
cd /opt/homelab
git status --short --branch
git branch --show-current
findmnt /srv/storage
df -h / /srv/storage
docker compose ps
make validate
```

- Stop if `/srv/storage` is not a real mount point.
- Do not pull with a dirty worktree. When clean, synchronize only with `git pull --ff-only`.
- Inspect the relevant Compose file, script, and runbook before changing a service.

## Mandatory checks after changes

Run the checks appropriate to the change:

```bash
make validate
docker compose ps
make doctor
docker compose logs --tail=100 SERVICE
git diff --check
git status --short
```

- Do not restart unrelated containers merely to verify documentation or configuration.
- For documentation-only changes, `make validate`, `make doctor`, and `git diff --check` are sufficient unless the documentation describes a failing live check.

## Secrets

- Never print, copy, commit, or expose `.env`, `.env.*`, `/etc/homelab`, passwords, tokens, private keys, or database credentials.
- Use placeholders in committed files and examples.
- Do not place secrets in command arguments, logs, issues, commit messages, or chat.
- Treat ignored secret-like backups, including `.env.before-restructure`, as sensitive. Do not open, move, or delete them without explicit approval.

## Safety gates

Do not perform any of the following without explicit user approval immediately before the action:

- format, partition, mount, unmount, or migrate disks or filesystems;
- edit `/etc/fstab`;
- delete or recursively change ownership under `/srv/appdata` or `/srv/storage`;
- run `docker compose down -v`, prune persistent data, or delete Docker volumes;
- delete databases, application state, backups, or Restic snapshots;
- change SSH authentication, firewall policy, router forwarding, or unrestricted sudo rules;
- expose ports publicly or open ports 22, 3389, or 9090 on the router;
- enable unattended updates for Immich, databases, or other stateful applications;
- initialize, replace, or reconfigure the Restic repository or backup timer;
- force-push or rewrite published Git history.

Prefer reversible operations and verify exact target paths before any destructive command.

## Docker Compose

- Base services start without a profile.
- Optional profiles are `nextcloud`, `immich`, `jellyfin`, `beszel-agent`, `timemachine`, and `agents`.
- Use the Makefile targets where available.
- Keep Homepage behind the read-only Docker socket proxy; do not restore a direct Docker socket mount.
- Keep Jellyfin media mounts read-only unless the user explicitly changes the storage policy.
- Review release notes before changing Immich or database image versions.
- Review release notes before changing the Open WebUI image version; keep Tools/Functions disabled until narrow agent services and approval gates exist in Git.
- Do not start a currently stopped service merely because its Compose file exists.

## Storage and databases

- Keep service configs, caches, and databases on the SSD under `/srv/appdata`.
- Keep user files, photos, media, backups, and restores under `/srv/storage`.
- Do not move raw PostgreSQL data directories to the HDD without a separate migration plan and approval.
- Back up PostgreSQL through verified database dumps; do not treat live raw database directories as a consistent backup.
- Existing photo archives must be added to Immich as External Libraries, initially read-only.

## Git

- Work on the current feature branch unless the user requests another branch.
- Make small focused commits with descriptive messages.
- Never commit `.env`, generated data, runtime state, certificates, secrets, or large media files.
- Never force-push.
- Before committing, review `git diff`, run `git diff --check`, and confirm the staged file list.

## Project constraints

- Do not add Paperless-ngx unless the user reverses the existing decision.
- Do not use VNC as the primary remote desktop solution.
- Prefer Tailscale plus OpenSSH for shell access, Cockpit for web administration, and GNOME Remote Desktop/RDP through Tailscale for graphical access.
- Time Machine must use Samba SMB with `vfs_fruit` and Avahi, with separate quotas for each Mac. Do not create an uncontrolled target on the current HDD.
