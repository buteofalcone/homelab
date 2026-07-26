SHELL := /usr/bin/env bash
COMPOSE := docker compose
PROFILES_ALL := --profile nextcloud --profile immich --profile jellyfin --profile beszel-agent

.DEFAULT_GOAL := help

.PHONY: help bootstrap validate install base apps nextcloud immich jellyfin beszel-agent \
        ps logs pull update update-all doctor health install-monitoring-timer backup snapshots restore \
        configure-cloudflare-dns caddy-reload stop down

help:
	@printf '%s\n' \
	  'make bootstrap      Create .env and generate passwords' \
	  'make validate       Validate Docker Compose configuration' \
	  'make install        Create host directories and start base services' \
	  'make base           Start management services and Caddy' \
	  'make nextcloud      Start Nextcloud stack' \
	  'make immich         Start Immich stack' \
	  'make jellyfin       Start Jellyfin' \
	  'make apps           Start all optional applications' \
	  'make beszel-agent   Start the local Beszel agent' \
	  'make ps             Show all containers' \
	  'make logs           Follow logs; SERVICE=name is optional' \
	  'make update         Update base services only' \
	  'make update-all     Update all enabled profiles' \
	  'make doctor         Run diagnostics' \
	  'make health         Run storage and SMART checks (requires sudo)' \
	  'make install-monitoring-timer  Install the 15-minute health timer' \
	  'make backup         Run Restic backup' \
	  'make snapshots      List Restic snapshots' \
	  'make configure-cloudflare-dns  Create private service DNS records' \
	  'make caddy-reload   Reload Caddyfile without downtime'

bootstrap:
	@./scripts/bootstrap.sh

validate:
	@./scripts/validate.sh

install:
	@sudo ./scripts/install.sh

base:
	@$(COMPOSE) up -d

nextcloud:
	@$(COMPOSE) --profile nextcloud up -d

immich:
	@$(COMPOSE) --profile immich up -d

jellyfin:
	@$(COMPOSE) --profile jellyfin up -d

apps:
	@$(COMPOSE) --profile nextcloud --profile immich --profile jellyfin up -d

beszel-agent:
	@$(COMPOSE) --profile beszel-agent up -d --no-deps beszel-agent

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
	@./scripts/update.sh nextcloud immich jellyfin beszel-agent

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

restore:
	@sudo ./scripts/restore.sh "$${SNAPSHOT:-latest}" "$${TARGET:-/srv/storage/restores/latest}"

configure-cloudflare-dns:
	@sudo ./scripts/configure-cloudflare-dns.sh

caddy-reload:
	@$(COMPOSE) exec -w /etc/caddy caddy caddy reload

stop:
	@$(COMPOSE) $(PROFILES_ALL) stop

down:
	@$(COMPOSE) $(PROFILES_ALL) down
