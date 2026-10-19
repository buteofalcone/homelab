# Storage Recovery Runbook

This runbook protects the stable `/srv/storage` contract during clean-machine recovery. It does not authorize the planned September 2026 HDD replacement.

## Non-negotiable rule

No homelab script selects, partitions, formats, mounts, unmounts, or adds a disk to `/etc/fstab` automatically. Those actions require a separate operator decision after identifying the physical device.

Never infer the target from a name such as `/dev/sdb`; device letters can change after reboot or hardware replacement.

## 1. Collect a read-only inventory

```bash
cd /opt/homelab
make storage-inventory
```

Record the intended disk's:

- model;
- serial number;
- capacity;
- filesystem type;
- filesystem UUID;
- expected existing contents.

`STORAGE_MOUNT_PRESENT` means `/srv/storage` is currently a separate mount. `STORAGE_ACTION_REQUIRED` means an operator must investigate before any container or restore job starts.

## 2. Decide which recovery case applies

### Existing homelab filesystem

Use this path only when the identified filesystem already contains the expected homelab data. Inspect it read-only at a temporary mount point before changing `/etc/fstab`. Substitute the verified UUID; do not paste the example literally.

```bash
sudo install -d -m 0755 /mnt/homelab-storage-check
sudo mount -o ro UUID=<VERIFIED-UUID> /mnt/homelab-storage-check
sudo find /mnt/homelab-storage-check -mindepth 1 -maxdepth 2 -printf '%P\n'
sudo umount /mnt/homelab-storage-check
```

Confirm that the displayed directories are the expected data. If they are not, stop.

### New empty disk

Partitioning and formatting are destructive and are outside the bootstrap. Defer this case until the actual HDD installation. Before proceeding then, record the new disk's model and serial, confirm backups, and obtain explicit approval for the exact device.

## 3. Add a verified existing filesystem to `/etc/fstab`

Only after the model, serial, UUID, filesystem type, and contents all agree:

1. Back up `/etc/fstab`.
2. Add one UUID-based entry for `/srv/storage`.
3. Validate the file before mounting.
4. Mount and verify the exact source and filesystem.

Example entry for the current ext4 storage contract:

```fstab
UUID=<VERIFIED-UUID> /srv/storage ext4 defaults,nofail,x-systemd.device-timeout=10 0 2
```

Verification commands:

```bash
sudo findmnt --verify --verbose
sudo install -d -m 0755 /srv/storage
sudo mount /srv/storage
findmnt --noheadings --output SOURCE,TARGET,FSTYPE,OPTIONS /srv/storage
make recovery-preflight
```

Proceed only when the source resolves to the verified filesystem and the preflight ends with `RECOVERY_PREFLIGHT_OK`.

## 4. Stop conditions

Stop and investigate if any of these occurs:

- the serial number or capacity differs from the planned disk;
- multiple filesystems could plausibly be the target;
- the filesystem is damaged, encrypted unexpectedly, or has an unknown type;
- the read-only inspection does not show expected data;
- `/srv/storage` resolves to the Ubuntu root filesystem;
- `findmnt --verify` reports an error;
- mounting would cover files already stored in the `/srv/storage` directory.
