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

The media mount is writable inside the container so an administrator can delete media from Jellyfin. Deleting an item removes the library file from `/srv/storage/media`; if it is a hardlink to a retained qBittorrent download, the download-side link and its disk usage remain until that torrent data is removed separately.

## Intel VA-API transcoding

The HP server's Intel iGPU is exposed with only `/dev/dri/renderD128`; Jellyfin joins the numeric `render` group from `JELLYFIN_RENDER_GID`. `scripts/bootstrap.sh` discovers that group ID on a clean Ubuntu installation. No `/dev/dri/card*` device is exposed.

Before enabling VA-API in Jellyfin's playback dashboard, verify the host driver:

```bash
sudo apt-get install vainfo i965-va-driver
sudo vainfo --display drm --device /dev/dri/renderD128
```
