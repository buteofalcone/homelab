# Immich Remote Machine Learning on SilverBrick

SilverBrick runs the Immich `v3.0.3-cuda` machine-learning container on its RTX 4060. The HP Server remains the source of truth for photos, PostgreSQL, and Immich application state. Only generated image previews cross the Tailscale connection for machine-learning inference.

The service deliberately publishes TCP 3003 only on SilverBrick's Tailscale address `100.91.171.26`. Immich Remote ML has no application authentication, so the Windows Firewall rule must additionally restrict the source to the HP Server at `100.65.83.35`.

## Install Docker Desktop

Run from PowerShell on SilverBrick:

```powershell
Set-Location C:\path\to\homelab
.\services\immich-remote-ml\install-docker-desktop.ps1
```

Complete Docker Desktop's first-run screen and wait until the Linux engine is running. No separate Ubuntu WSL distribution is required for Docker Desktop's managed WSL2 backend.

If Docker reports `HCS_E_HYPERV_NOT_INSTALLED`, the WSL package exists but Windows **Virtual Machine Platform** is disabled. Verify that CPU virtualization is enabled in BIOS, then run this script from an elevated PowerShell window and restart Windows when it prints `WSL_PLATFORM_ENABLED_RESTART_REQUIRED`:

```powershell
.\services\immich-remote-ml\enable-wsl-platform.ps1
```

If both optional components are enabled but Docker still reports `HCS_E_HYPERV_NOT_INSTALLED`, verify the current boot entry with `bcdedit /enum {current}` from an elevated shell. A deliberately disabled hypervisor appears as `hypervisorlaunchtype Off`. The following reviewed script changes only that value to `Auto`; restart Windows again when it prints its success marker:

```powershell
.\services\immich-remote-ml\enable-hypervisor-launch.ps1
```

## Audit CUDA

```powershell
.\services\immich-remote-ml\audit.ps1
```

This verifies Docker, the expected Tailscale address, the Windows NVIDIA driver, and GPU access from an isolated CUDA container.

## Firewall and deployment

Apply the firewall script from an elevated PowerShell window only after reviewing the exact HP Server and SilverBrick Tailscale addresses:

```powershell
.\services\immich-remote-ml\restrict-firewall.ps1
.\services\immich-remote-ml\deploy.ps1
.\services\immich-remote-ml\verify.ps1
```

The Compose project uses a named Docker volume for `/cache`, so downloaded ML models survive container replacement. Keep the CUDA image version exactly synchronized with the HP Server's Immich version.

## Immich setting

After the remote verification succeeds, add these URLs in **Immich Administration → Settings → Machine Learning** in this order:

1. `http://100.91.171.26:3003`
2. `http://immich-machine-learning:3003`

The local container remains the fallback whenever SilverBrick is asleep. Do not configure router port forwarding, Cloudflare proxying, Caddy, or public DNS for TCP 3003.

## Upgrade contract

Read the Immich release notes first. In one reviewed commit, update the HP Server `IMMICH_VERSION`, the server and local-ML defaults, and the SilverBrick CUDA image. Upgrade both machines during the same maintenance window and verify both ML URLs before running new jobs.
