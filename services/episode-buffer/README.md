# Rolling episode buffer

This service connects the primary Jellyfin user's watched state to Sonarr. It is intentionally opt-in and manages only Sonarr series tagged `rolling-3`.

For a newly watched episode older than the grace period it:

1. unmonitors the watched episode;
2. asks Sonarr to delete its episode file, which moves it to `/data/recycle/sonarr`;
3. monitors the next three numbered episodes;
4. starts an Episode Search for missing episodes that have already aired.

The Sonarr tag `keep` always wins and blocks all actions. Movies, specials, unmanaged series, and the pre-install watched history are ignored.

## Setup

Create a dedicated Jellyfin API key in **Dashboard → API Keys**. Then run:

```bash
sudo make episode-buffer-configure
sudo make episode-buffer-install
sudo make episode-buffer-verify
```

Configuration starts in `dry-run`. Add the `rolling-3` tag to one test series in Sonarr, watch an episode, wait for the 24-hour grace period (or temporarily lower it in `/etc/homelab/episode-buffer.env`), and inspect:

```bash
sudo journalctl -u homelab-episode-buffer.service --since today
```

After reviewing the dry-run output, activation requires a separate explicit confirmation:

```bash
sudo make episode-buffer-activate
```

Sonarr's Recycle Bin retains removed files for seven days. qBittorrent seeding is separate: hard-linked torrent data remains until qBittorrent reaches its configured seed goal.

Season-pack torrents may still download a complete season even though the library buffer contains only three episodes.
