# Architecture

The repository contains declarative Docker Compose configuration and host-side recovery scripts.

Persistent container state is stored under `/srv/appdata` on the system SSD. Large user data and Restic repositories are stored under `/srv/storage` on the HDD.

The default Docker bridge network is named `homelab`.
