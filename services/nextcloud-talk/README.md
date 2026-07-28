# Nextcloud Talk

Nextcloud Talk provides the private family text chat inside the existing Nextcloud service. It does not add another database, domain, or container.

## Provisioning

```bash
make nextcloud-talk-bootstrap
```

The helper is idempotent. It requires the running Nextcloud 33.x stack, installs or enables the official `spreed` app, and verifies the compatible Talk 23.x release, app integrity, OCC commands, and private HTTPS route.

Run the read-only checks again with:

```bash
make nextcloud-talk-verify
```

## Family use

Each family member uses their own Nextcloud account in the Nextcloud Talk mobile app or at `https://nextcloud.butenko.online/apps/spreed/`. Create a private conversation or a family group and invite those accounts.

Text chat and file sharing do not require a separate TURN server or High Performance Backend. Audio and video calls use the built-in WebRTC path initially. Add TURN or HPB only if a later call test demonstrates that it is necessary.

## Backup boundary

Conversation state is stored in the Nextcloud PostgreSQL database, and the installed app is under `/srv/appdata/nextcloud`; both are covered by the existing application backup. Files shared through Talk remain Nextcloud user data under `/srv/storage/files/nextcloud`, so they still require the planned external or off-site backup.
