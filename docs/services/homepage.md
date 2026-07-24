# Homepage

Homepage is the landing page for the server. Its configuration is versioned under `config/homepage` and copied into `/srv/appdata/homepage` during installation.

After changing its static configuration, rerun:

```bash
sudo ./scripts/install.sh
docker compose restart homepage
```
