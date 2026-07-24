# Jellyfin

Start:

```bash
make jellyfin
```

Direct URL: `http://SERVER_IP:8096`  
HTTPS URL: `https://jellyfin.BASE_DOMAIN`

Media directories:

```text
/srv/storage/media/Movies
/srv/storage/media/TV
/srv/storage/media/Music
/srv/storage/media/HomeVideos
```

The media mount is read-only inside the container. Hardware acceleration is not enabled by default.
