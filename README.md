# HP Homelab

Автоматизований post-install для Ubuntu 24.04 LTS.

## Перший запуск

```bash
REPO_URL=https://github.com/YOUR_USERNAME/homelab.git \
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/homelab/main/bootstrap.sh)
```

Результат:
- hostname `hp-server`
- SSH
- Docker Engine
- Docker Compose
- UFW
- unattended-upgrades
- каталоги `/srv/homelab`
- Homepage на `http://SERVER_IP:3000`
