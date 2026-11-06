# Rolling episode buffer

This service connects the primary Jellyfin user's watched state to Sonarr. By default it manages every Sonarr series automatically, including newly requested series from Seerr.

For a newly watched episode older than the grace period it:

1. unmonitors the watched episode;
2. asks Sonarr to delete its episode file, which moves it to `/data/recycle/sonarr`;
3. monitors the next three numbered episodes;
4. starts an Episode Search for missing episodes that have already aired.

The Sonarr tag `keep` always wins and blocks all actions. Movies, specials, and the pre-install watched history are ignored. Set `EPISODE_BUFFER_MANAGE_ALL=false` to return to selective mode, where only series tagged `rolling-3` are managed.

## Setup

Create a dedicated Jellyfin API key in **Dashboard → API Keys**. Then run:

```bash
sudo make episode-buffer-configure
sudo make episode-buffer-install
sudo make episode-buffer-verify
```

Configuration becomes active immediately after a safe baseline records the existing watched history. All series are managed automatically; add the `keep` tag in Sonarr to protect a series from rolling deletion. Newly watched episodes are evaluated by the next timer run. Inspect activity with:

```bash
sudo journalctl -u homelab-episode-buffer.service --since today
```

Sonarr's Recycle Bin retains removed files for seven days. qBittorrent seeding is separate: hard-linked torrent data remains until qBittorrent reaches its configured seed goal.

Season-pack torrents may still download a complete season even though the library buffer contains only three episodes.
