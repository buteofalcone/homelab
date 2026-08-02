SHELL := /usr/bin/env bash
COMPOSE := docker compose
PROFILES_ALL := --profile nextcloud --profile immich --profile jellyfin --profile beszel-agent --profile timemachine --profile agents --profile books --profile media-automation

.DEFAULT_GOAL := help

.PHONY: help bootstrap host-bootstrap recovery-preflight storage-inventory validate install homepage-deploy base apps nextcloud nextcloud-talk-bootstrap nextcloud-talk-verify immich immich-pin-version immich-remote-ml-configure immich-migration-bootstrap immich-migration-api-key immich-migration-api-key-verify immich-takeout-preflight immich-takeout-dry-run jellyfin beszel-agent timemachine timemachine-bootstrap open-webui open-webui-bootstrap calibre calibre-bootstrap calibre-import calibre-verify calibre-migration-preflight calibre-migration-apply calibre-merge-preflight calibre-merge-apply media-automation-bootstrap media-automation-verify media-automation-toloka media-automation-test media-automation-test-verify repair-family-access rdp-reconfigure \
        ps logs pull update update-all doctor health install-monitoring-timer backup snapshots restore verify-backup verify-restore verify-database-restore verify-management-restore post-restore-check \
        check-lm-studio configure-cloudflare-dns caddy-reload stop down

help:
	@printf '%s\n' \
	  'make bootstrap      Create .env and generate passwords' \
	  'make host-bootstrap Install clean Ubuntu host prerequisites (requires sudo)' \
	  'make recovery-preflight  Read-only clean-host prerequisite checks' \
	  'make storage-inventory   Read-only disk and /srv/storage inventory' \
	  'make validate       Validate Docker Compose configuration' \
	  'make install        Create host directories and start base services' \
	  'make homepage-deploy  Publish tracked Homepage configuration (requires sudo)' \
	  'make base           Start management services and Caddy' \
	  'make nextcloud      Start Nextcloud stack' \
	  'make nextcloud-talk-bootstrap  Install and enable compatible Nextcloud Talk' \
	  'make nextcloud-talk-verify  Verify Nextcloud Talk application state' \
	  'make immich         Start Immich stack' \
	  'make immich-pin-version  Pin live Immich release to the verified exact version' \
	  'make immich-remote-ml-configure  Prefer SilverBrick ML with local fallback' \
	  'make immich-migration-bootstrap  Install pinned immich-go and Takeout staging' \
	  'make immich-migration-api-key    Store a dedicated root-only Immich API key' \
	  'make immich-migration-api-key-verify  Validate the stored key without exposing it' \
	  'make immich-takeout-preflight    Validate and fingerprint the small Takeout sample' \
	  'make immich-takeout-dry-run      Simulate the sample import without mutations' \
	  'make jellyfin       Start Jellyfin' \
	  'make apps           Start all optional applications' \
	  'make beszel-agent   Start the local Beszel agent' \
	  'make timemachine-bootstrap  Provision Time Machine secrets, storage and Avahi' \
	  'make timemachine    Start the provisioned Time Machine service' \
	  'make repair-family-access  Recover SMB, writable Jellyfin media, SSH, and audit RDP' \
	  'make rdp-reconfigure  Reset GNOME Remote Desktop credentials and security' \
	  'make calibre-migration-preflight  Validate a staged Mac Calibre library' \
	  'make calibre-migration-apply      Replace the test library with validated staging' \
	  'make open-webui-bootstrap  Provision secrets and start private AI chat' \
	  'make open-webui     Start the provisioned private AI chat' \
	  'make calibre-bootstrap  Provision and start full Calibre' \
	  'make calibre        Start the provisioned Calibre services' \
	  'make calibre-import BOOK=/srv/storage/incoming/books/file  Convert and import one book' \
	  'make calibre-verify Run disposable Calibre conversion and service checks' \
	  'make media-automation-bootstrap  Provision qBittorrent, Sonarr, Prowlarr, Radarr, and Seerr' \
	  'make media-automation-verify  Verify media paths, auth and idle state' \
	  'make media-automation-toloka  Securely configure the private Toloka.to indexer' \
	  'make media-automation-test-verify  Verify the public-domain import and hardlink' \
	  'make ps             Show all containers' \
	  'make logs           Follow logs; SERVICE=name is optional' \
	  'make update         Update base services only' \
	  'make update-all     Update all enabled profiles' \
	  'make doctor         Run diagnostics' \
	  'make health         Run storage and SMART checks (requires sudo)' \
	  'make install-monitoring-timer  Install the 15-minute health timer' \
	  'make backup         Run Restic backup' \
	  'make snapshots      List Restic snapshots' \
	  'make verify-backup  Check Restic and PostgreSQL dumps' \
	  'make verify-restore Restore and verify a small safe sample' \
	  'make verify-database-restore  Import restored dumps into disposable databases' \
	  'make verify-management-restore  Restore management state into an audit directory' \
	  'make post-restore-check  Verify the recovered host and applications' \
	  'make check-lm-studio  Verify authenticated SilverBrick model API' \
	  'make configure-cloudflare-dns  Create private service DNS records' \
	  'make caddy-reload   Reload Caddyfile without downtime'

bootstrap:
	@./scripts/bootstrap.sh

host-bootstrap:
	@sudo ./scripts/bootstrap-host.sh

recovery-preflight:
	@./scripts/recovery-preflight.sh

storage-inventory:
	@./scripts/storage-inventory.sh

validate:
	@./scripts/validate.sh

install:
	@sudo ./scripts/install.sh

homepage-deploy:
	@sudo ./scripts/deploy-homepage.sh

base:
	@$(COMPOSE) up -d

nextcloud:
	@$(COMPOSE) --profile nextcloud up -d

nextcloud-talk-bootstrap:
	@./services/nextcloud-talk/bootstrap.sh

nextcloud-talk-verify:
	@./services/nextcloud-talk/verify.sh

immich:
	@$(COMPOSE) --profile immich up -d

immich-pin-version:
	@sudo ./services/immich-migration/pin-immich-version.sh

immich-remote-ml-configure:
	@sudo ./services/immich-migration/configure-remote-ml.sh

immich-migration-bootstrap:
	@sudo ./services/immich-migration/bootstrap.sh

immich-migration-api-key:
	@sudo ./services/immich-migration/configure-api-key.sh

immich-migration-api-key-verify:
	@sudo ./services/immich-migration/verify-api-key.sh

immich-takeout-preflight:
	@sudo ./services/immich-migration/preflight.sh

immich-takeout-dry-run:
	@sudo ./services/immich-migration/dry-run.sh

jellyfin:
	@$(COMPOSE) --profile jellyfin up -d

apps:
	@$(COMPOSE) --profile nextcloud --profile immich --profile jellyfin up -d

beszel-agent:
	@$(COMPOSE) --profile beszel-agent up -d --no-deps beszel-agent

timemachine-bootstrap:
	@sudo ./services/timemachine/bootstrap.sh

timemachine:
	@$(COMPOSE) --profile timemachine up -d --build timemachine

repair-family-access:
	@sudo ./scripts/repair-family-access.sh

rdp-reconfigure:
	@./scripts/configure-rdp.sh

open-webui-bootstrap:
	@sudo ./services/open-webui/bootstrap.sh

open-webui:
	@$(COMPOSE) --profile agents up -d open-webui

calibre-bootstrap:
	@sudo ./services/calibre/bootstrap.sh

calibre-migration-preflight:
	@sudo ./services/calibre/migration-preflight.sh

calibre-migration-apply:
	@sudo ./services/calibre/migrate-library.sh

calibre-merge-preflight:
	@sudo ./services/calibre/migration-preflight.sh /srv/storage/incoming/calibre-merge

calibre-merge-apply:
	@sudo ./services/calibre/merge-library.sh

calibre:
	@$(COMPOSE) --profile books up -d calibre

calibre-import:
	@./services/calibre/import-book.sh "$${BOOK:-}"

calibre-verify:
	@./services/calibre/verify.sh

media-automation-bootstrap:
	@sudo ./services/media-automation/bootstrap.sh

media-automation-verify:
	@sudo ./services/media-automation/verify.sh

media-automation-connect:
	@sudo ./services/media-automation/configure-integrations.sh

media-automation-toloka:
	@sudo ./services/media-automation/configure-toloka.sh

media-automation-test:
	@sudo ./services/media-automation/test-public-domain-episode.sh

media-automation-test-verify:
	@./services/media-automation/verify-public-domain-test.sh

ps:
	@$(COMPOSE) $(PROFILES_ALL) ps

logs:
	@if [[ -n "$${SERVICE:-}" ]]; then \
	  $(COMPOSE) logs -f --tail=200 "$${SERVICE}"; \
	else \
	  $(COMPOSE) $(PROFILES_ALL) logs -f --tail=200; \
	fi

pull:
	@$(COMPOSE) $(PROFILES_ALL) pull

update:
	@./scripts/update.sh

update-all:
	@./scripts/update.sh nextcloud immich jellyfin beszel-agent agents books media-automation

doctor:
	@./scripts/doctor.sh

health:
	@sudo ./scripts/health-check.sh

install-monitoring-timer:
	@sudo ./scripts/install-monitoring-timer.sh

backup:
	@sudo ./scripts/backup.sh

snapshots:
	@sudo ./scripts/restic.sh snapshots

verify-backup:
	@sudo ./scripts/verify-backup.sh

verify-restore:
	@sudo ./scripts/verify-restore.sh

verify-database-restore:
	@sudo ./scripts/verify-database-restore.sh

verify-management-restore:
	@sudo ./scripts/verify-management-restore.sh

post-restore-check:
	@./scripts/post-restore-check.sh

check-lm-studio:
	@sudo ./scripts/check-lm-studio.sh

restore:
	@sudo ./scripts/restore.sh "$${SNAPSHOT:-latest}" "$${TARGET:-/srv/storage/restores/latest}"

configure-cloudflare-dns:
	@sudo ./scripts/configure-cloudflare-dns.sh

caddy-reload:
	@$(COMPOSE) exec -w /etc/caddy caddy /bin/sh -c \
	  'set -a; . /run/secrets/caddy.env; [ ! -f /run/secrets/media-caddy.env ] || . /run/secrets/media-caddy.env; set +a; exec caddy reload --config Caddyfile'

stop:
	@$(COMPOSE) $(PROFILES_ALL) stop

down:
	@$(COMPOSE) $(PROFILES_ALL) down
