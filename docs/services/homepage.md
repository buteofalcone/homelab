# Homepage

Homepage is the landing page for the server. Its configuration is versioned under `config/homepage` and copied into `/srv/appdata/homepage` during installation.

After changing its static configuration, rerun:

```bash
make homepage-deploy
```

The command copies only the tracked Homepage configuration, preserves its generated environment file, validates the Compose model, and restarts only Homepage.
