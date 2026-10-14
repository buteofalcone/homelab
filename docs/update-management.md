# Update management

The server uses two deliberately separate update paths.

## Ubuntu packages

Cockpit's **Software Updates** page is provided by `cockpit-packagekit`. It can review and apply normal Ubuntu updates from the existing Cockpit interface. Nala is installed as the clearer terminal frontend for package discovery and installation:

```bash
sudo nala update
nala list --upgradable
sudo nala upgrade
sudo nala install PACKAGE
```

Package installation remains an explicit administrator action. Unattended host upgrades are not enabled.

## Docker images

Renovate scans tracked Compose files and opens pull requests in GitHub. It pins mutable image tags to digests, proposes patch/minor/digest updates, and never merges automatically. Major Docker image upgrades are disabled and must be planned separately.

Install the Renovate GitHub App for `buteofalcone/homelab`, then review its Dependency Dashboard and pull requests. Merge only after reading release notes for stateful services such as Immich, Nextcloud, databases, Open WebUI, and Seerr.

Watchtower runs in global monitor-only mode. It may pull image metadata and report an available image, but it never replaces or restarts an application container.

## Routine workflow

Check available changes:

```bash
cd /opt/homelab
sudo make update-check
```

After reviewing and merging Renovate pull requests:

```bash
cd /opt/homelab
sudo make update
```

The update command refuses a dirty repository or a missing `/srv/storage` mount. It fast-forwards Git, validates Compose, runs the Restic/database backup, records the currently running Compose services, pulls or builds only those services, and recreates only already-running services whose image or configuration changed. Stopped profiles remain stopped.

Do not use Portainer's image-update action for normal maintenance because it changes runtime state without updating Git. Portainer remains useful for status, logs, and troubleshooting.
