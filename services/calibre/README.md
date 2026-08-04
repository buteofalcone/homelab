# Full Calibre

This service runs the complete Calibre 9.11 desktop application and CLI tools. It is intentionally not Calibre-Web.

## Storage

- `/srv/appdata/calibre` — GUI preferences and application state on the SSD.
- `/srv/storage/books` — the Calibre library, including books and `metadata.db`, on the HDD.
- `/srv/storage/incoming/books` — read-only input area for controlled imports.
- `/srv/storage/incoming/calibre-migration` — staging for one complete library copied from a closed desktop Calibre.
- `/srv/storage/incoming/calibre-merge` — staging for one additional complete library at a time.
- `/etc/homelab/calibre-gui-password` — root-only web-desktop password.

The library remains at the same host path when the temporary HDD is cloned to the final 8–16 TB disk.

## Provisioning

```bash
make calibre-bootstrap
```

The bootstrap creates directories and the root-only GUI password, initializes a small generated EPUB on a fresh library, selects the library path, enables Calibre's built-in Content Server, and waits for the combined health check.

Administrative GUI: `https://calibre.butenko.online`

Family library: `https://books.butenko.online`

OPDS catalog: `https://books.butenko.online/opds`

Legacy LAN-only OPDS catalog: `http://192.168.1.130:8081/opds`. Docker binds this port only to `SERVER_IP`, so an iOS 9 device can read books on trusted home Wi-Fi without Tailscale. TCP 8081 must not be forwarded on the router.

The GUI is sensitive because a full desktop application can access its mounted paths. It is protected by a dedicated password, terminal and sudo features are disabled, and the service is reachable only through the private Tailscale address. Do not share its password with family readers.

The Content Server runs inside the same Calibre process. This is required because two independent Calibre processes must not open the same mutable library. Family access is routed only to port 8081 and does not expose the administration desktop. It has no additional application password because its DNS address is private to the tailnet; review Tailscale sharing policy before inviting family members.

## Import and conversion

Copy one source book into `/srv/storage/incoming/books`, then run:

```bash
make calibre-import BOOK=/srv/storage/incoming/books/example.pdf
```

The SMB path `Inbox/books` maps to that server directory. Copying files does not import them automatically. To import every supported file currently staged there, run:

```bash
make calibre-import-inbox
```

The batch command processes nested folders and filenames with spaces, reports each failure, and deliberately leaves the source files in place. It also recognizes an exploded `.epub` directory containing `META-INF/container.xml` and rebuilds it from its OPF package document instead of importing internal bookmark or metadata files. After checking the imported titles in Books, archive or remove the staged sources to prevent an accidental repeat import.

Supported controlled inputs are AZW3, DOCX, EPUB, FB2, HTML, LIT, MOBI, ODT, PDF, RTF and TXT. Non-EPUB input is converted with `ebook-convert`, validated with `ebook-meta`, then added with `calibredb`. The source is deliberately retained until the imported result is checked.

PDF conversion is best-effort because PDFs encode page layout rather than ebook structure.

## Migrating an existing Mac library

1. Quit Calibre completely on the Mac.
2. Mount `smb://100.65.83.35/Inbox` and copy the contents of the Mac's Calibre library into `calibre-migration`. The top level must contain `metadata.db` and the author directories.
3. Keep the original Mac library unchanged, then run:

```bash
make calibre-migration-preflight
```

4. Review the reported book, file, and byte counts. The apply command requires an explicit `MIGRATE_CALIBRE` confirmation:

```bash
make calibre-migration-apply
```

The apply step stops only Calibre, preserves the existing server library as `/srv/storage/books.before-calibre-migration-TIMESTAMP`, moves the validated staging directory into `/srv/storage/books`, recreates an empty staging directory, and starts Calibre. If the new library does not become healthy, the script restores the previous library and preserves the failed import separately. Do not delete either Mac or server fallback copy until the Content server, metadata, covers, and several EPUB downloads have been checked.

## Merging additional libraries

Copy one closed additional Calibre library at a time into `Inbox/calibre-merge`; its `metadata.db` must be directly inside that directory. Then run:

```bash
make calibre-merge-preflight
make calibre-merge-apply
```

The apply command requires the explicit phrase `MERGE_CALIBRE`. It exports the source through Calibre so OPF metadata, covers, formats, and extra files are retained, using a short ID-only export layout to stay below filesystem filename limits. It creates a timestamped rollback copy of the live library and imports with `--automerge ignore`. A matching title/author gains missing formats without overwriting an existing same-format file. The staged source is retained as `calibre-merge.completed-TIMESTAMP` until the resulting library and backup are verified.

Run a disposable conversion and library smoke test with:

```bash
make calibre-verify
```

## iPad

Open the family library URL in Safari, select a book, download its EPUB and choose **Open in Books**. OPDS-capable readers can use the `/opds` URL. Apple Books does not synchronize a private OPDS catalog automatically, so downloads are an explicit per-book action.

## Backup boundary

Restic protects the SSD configuration under `/srv/appdata`, but it does not copy the HDD-resident library back onto the same HDD. `/srv/storage/books` requires an external or off-site backup before it becomes the only copy of a book collection.
