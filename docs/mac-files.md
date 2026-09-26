# Mac file workflow

## Private server access

Keep Tailscale running at login on the Mac. In the Tailscale menu-bar application open **Settings** and enable **Start Tailscale at login**. If it is disconnected, open Tailscale through Spotlight and select **Connect**. Because MagicDNS is unreliable on the Monterey/OCLP Mac, use the stable server address `100.65.83.35`.

Mount the private staging share in Finder with **Go -> Connect to Server**:

```text
smb://100.65.83.35/Inbox
```

Store the dedicated `homelab` SMB account in Keychain. Do not use either Time Machine account.

## Documents and Google Drive migration

Use the Nextcloud Desktop client with `https://nextcloud.butenko.online` and a separate local directory such as `~/Nextcloud`. Do not let Google Drive and Nextcloud synchronize the same physical directory: two independent sync engines can create conflicting renames, deletions, and duplicate files.

Safe migration:

1. Keep Google Drive running while creating an empty `~/Nextcloud` directory.
2. Connect that directory to Nextcloud Desktop.
3. Copy, rather than move, the required Google Drive documents into `~/Nextcloud/Documents`.
4. Wait for Nextcloud to finish, then compare representative files in the browser and on a phone.
5. Keep the Google Drive copy unchanged for an agreed safety period before disabling its old sync.

If a second cloud copy is required later, implement a controlled server-side backup. Do not use two live desktop sync clients on the same folder as a backup mechanism.

## Sharing files

Inside the family, use normal Nextcloud user/group shares or Talk. Nextcloud public links can provide download-only access, passwords, expiration dates, and file-drop uploads, but the current `nextcloud.butenko.online` address remains private to the tailnet. Public Internet delivery is therefore a separate ingress milestone.

Cloudflare Tunnel is explicitly excluded. Until another ingress method is selected and security-reviewed, do not forward SMB or Nextcloud ports on the router and do not describe a private Nextcloud link as publicly reachable.
