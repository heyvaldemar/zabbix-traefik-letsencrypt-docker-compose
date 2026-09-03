# Zabbix + Traefik + Let's Encrypt on Docker Compose

[![Deployment Verification](https://github.com/heyvaldemar/zabbix-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/zabbix-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Contents

- [Why this stack?](#why-this-stack)
- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
- [Features](#features)
  - [Typical use cases](#typical-use-cases)
- [Supply chain trust](#supply-chain-trust)
- [Production checklist](#production-checklist)
- [Backups](#backups)
- [Testing](#testing)
- [Security Notes](#security-notes)
- [About the maintainer](#about-the-maintainer)

This repository deploys a full Zabbix 7.0 LTS monitoring stack (server, nginx web frontend, and agent2) behind Traefik with automatic Let's Encrypt TLS, backed by PostgreSQL, with a scheduled backup container and a companion restore script. Agent traffic (TCP and UDP 10051) is routed through dedicated Traefik entrypoints. One `docker compose up` away from production-shaped infrastructure monitoring at `https://your-domain`.

📙 Full narrative installation guide on the blog: [heyvaldemar.com/install-zabbix-using-docker-compose/](https://www.heyvaldemar.com/install-zabbix-using-docker-compose/).

## Why this stack?

| Need | This stack | Manual install | Kubernetes | Other compose examples |
|------|-----------|----------------|------------|------------------------|
| Ready to deploy in <10 min | ✅ | ❌ hours of setup | ✅ if K8s is already running | Often |
| TLS via Let's Encrypt, auto-renewed | ✅ Traefik ACME built-in | Manual certbot | Via cert-manager | Rare |
| LTS line (supported to 2029) | ✅ 7.0 LTS pinned | Your choice | Varies | Often EOL versions |
| Server + web + agent2 wired together | ✅ | Three installs | ✅ | Varies |
| Agent TCP/UDP routed via proxy entrypoints | ✅ | Manual firewalling | Service/LB config | Rare |
| Scheduled DB backups + pruning | ✅ | Manual cron | External | Rare |
| Upstream images pinned by `sha256` digest | ✅ | N/A | Depends | Rare |
| Weekly pin-freshness check in CI | ✅ LTS-line aware | N/A | Depends | Rare |
| CI-verified deployment on every push | ✅ web API answers | N/A | Varies | Rare |
| Credentials via env (never committed) | ✅ | N/A | K8s Secrets | Often committed plaintext |

Six moving parts (Traefik + server + web + agent + Postgres + backups). No Kubernetes prerequisites, no manual certificate management.

## Prerequisites

Before you start, you need:

- **A Linux server** with a public IP. Tested on Ubuntu 22.04 LTS+ and Debian 12+. Local Mac/Windows works for dev; production is Linux.
- **Docker Engine 24+ and Docker Compose 2.20+.** Quick check: `docker version` and `docker compose version`.
- **A domain you control,** with two `A` records pointing at your server's public IP: one for the Zabbix dashboard (e.g. `dashboard.zabbix.example.com`), one for the Traefik dashboard (e.g. `traefik.zabbix.example.com`). DNS must propagate before deploy or the Let's Encrypt TLS-ALPN challenge will fail.
- **Ports 80, 443, and 10051 open** on the server's firewall: 10051 (TCP/UDP) receives data from remote Zabbix agents.
- **~2 GB free RAM and 1 free CPU** for the running stack; Postgres and the server cache grow with the number of monitored hosts.

## Getting started

```bash
# 1. Clone
git clone https://github.com/heyvaldemar/zabbix-traefik-letsencrypt-docker-compose
cd zabbix-traefik-letsencrypt-docker-compose

# 2. Create the two Docker networks the stack expects
docker network create traefik-network
docker network create zabbix-network

# 3. Copy the environment template and fill in required values
cp .env.example .env
$EDITOR .env
# ^ Required: ZABBIX_DB_PASSWORD, ZABBIX_DASHBOARD_HOSTNAME,
#   TRAEFIK_HOSTNAME, TRAEFIK_ACME_EMAIL, TRAEFIK_BASIC_AUTH.
#   See .env.example for generation commands.

# 4. Deploy
docker compose -f zabbix-traefik-letsencrypt-docker-compose.yml -p zabbix up -d
```

Within a couple of minutes `https://${ZABBIX_DASHBOARD_HOSTNAME}` serves the Zabbix login page with a fresh Let's Encrypt certificate. Default credentials are Zabbix's stock `Admin` / `zabbix`: change them immediately (see the checklist).

### What success looks like

```bash
# All services healthy (server schema init takes a minute on first boot):
docker compose -f zabbix-traefik-letsencrypt-docker-compose.yml -p zabbix ps

# The web API answers with the running version:
curl -fsS -X POST "https://${ZABBIX_DASHBOARD_HOSTNAME}/api_jsonrpc.php" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"apiinfo.version","params":{},"id":1}'
# Expected: {"jsonrpc":"2.0","result":"7.0.30","id":1}

# Traefik issued a certificate:
docker compose -p zabbix logs traefik | grep -i "adding certificate"

# First backup lands after ZABBIX_BACKUP_INIT_SLEEP (default 30m):
docker compose -p zabbix logs backups | tail -3
```

### Common first-deploy issues

- **Cert issuance fails.** DNS hasn't propagated or port 80 isn't reachable from the internet. Confirm with `dig +short ${ZABBIX_DASHBOARD_HOSTNAME}` and `curl -I http://${ZABBIX_DASHBOARD_HOSTNAME}` from outside the server.
- **`docker compose up` fails with `set in .env`.** A required variable is empty; the error names it.
- **`network zabbix-network not found`.** Step 2 was skipped.
- **Server restarts while Postgres initializes.** On very first boot the server creates the full schema; give it a minute and check `docker compose -p zabbix logs zabbix-server`.

### Apply `.env` or compose-file changes

```bash
docker compose -f zabbix-traefik-letsencrypt-docker-compose.yml -p zabbix up -d --force-recreate
```

## Features

- **Zabbix 7.0 LTS** (supported until 2029), server, nginx web frontend, and agent2 images move together.
- **Traefik v3** reverse proxy with automatic HTTP→HTTPS redirect and Let's Encrypt TLS-ALPN certificate issuance.
- **Dedicated TCP and UDP entrypoints on 10051** so remote agents reach the server through Traefik.
- **Bundled agent2** monitoring the Docker host itself out of the box.
- **Basic-auth protected Traefik dashboard** on a separate hostname.
- **Scheduled PostgreSQL backups** with configurable interval, retention, and destination path, plus a restore script.
- **Healthchecks** on every service with start-order dependencies.
- **Credentials required at deploy time**: compose fails fast if `.env` is incomplete.

### Typical use cases

- **Infrastructure monitoring for a fleet**: servers, network gear (SNMP), services, certificates.
- **Homelab observability**: one box watching everything else, with escalations to email/Telegram.
- **SMB monitoring without SaaS pricing**: Zabbix is fully featured with no per-host fees.
- **Staging ground for enterprise Zabbix**: validate the 7.0 LTS shape before a larger rollout.

## Supply chain trust

This repository is a deployment template, not a custom Docker image. It orchestrates five upstream images:

- [`traefik`](https://hub.docker.com/_/traefik): reverse proxy, Docker Hub official image
- [`zabbix/zabbix-server-pgsql`](https://hub.docker.com/r/zabbix/zabbix-server-pgsql), [`zabbix/zabbix-web-nginx-pgsql`](https://hub.docker.com/r/zabbix/zabbix-web-nginx-pgsql), [`zabbix/zabbix-agent2`](https://hub.docker.com/r/zabbix/zabbix-agent2), Zabbix upstream
- [`postgres`](https://hub.docker.com/_/postgres): PostgreSQL, Docker Hub official image

All five are pinned to `tag@sha256:<digest>` as interpolation defaults in the compose file's `x-images` block. Compose pulls by digest, not by tag, and `git pull` alone delivers the version combination this repository has tested. Setting an `*_IMAGE_TAG` variable in `.env` overrides the default when you deliberately want a different version.

Two override levels exist per image. `<PREFIX>_IMAGE_VERSION` in `.env` swaps only the version of that image (Compose then pulls the tag, without a digest) and leaves every other pin as tested; `<PREFIX>_IMAGE_TAG` replaces the whole reference, digest included. The variable names are listed in `.env.example`. Nested defaults need Docker Compose v2.5 or newer (2022); v2.0 to v2.4 leave the inner `${...}` unexpanded and `docker compose up` fails with an invalid reference instead of deploying something unexpected.

The daily `check-pin-freshness` CI job re-resolves each pinned tag against its registry, compares the pinned Zabbix version against the latest patch of its LTS line via endoflife.date (and fails loudly if the line itself goes end-of-life), and checks the Traefik minor against the latest upstream release. CI's Deployment Verification workflow runs on every push, pull request, and every day at 06:00 UTC. GitHub Actions are pinned by commit SHA; Dependabot keeps those fresh.

## Production checklist

Before relying on this for real monitoring, check every box:

- [ ] **Change the stock frontend login.** Zabbix ships `Admin` / `zabbix`: change it on first login and create named users.
- [ ] **Strong secrets.** `ZABBIX_DB_PASSWORD` at 24+ random characters; regenerate the Traefik dashboard BCrypt hash per deployment.
- [ ] **Decide about port 10051 exposure.** If all monitored hosts are on your networks, restrict source IPs on the firewall.
- [ ] **Host-mount the backups volume** for disaster recovery: bind `ZABBIX_POSTGRES_BACKUPS_PATH` to a host path covered by your off-host backup solution.
- [ ] **Verify Let's Encrypt cert issuance** in the Traefik logs on first start.
- [ ] **Tune `ZABBIX_CACHESIZE`** (default 1G) to your host count.
- [ ] **Plan upgrades within the LTS line.** The pins track 7.0 LTS; the server migrates the schema automatically on minor bumps. Back up first: there is no downgrade path.

## Backups

The `backups` container performs a `pg_dump | gzip` → prune → sleep loop against the Zabbix database. All knobs (`ZABBIX_BACKUP_INIT_SLEEP`, `ZABBIX_BACKUP_INTERVAL`, `ZABBIX_POSTGRES_BACKUP_PRUNE_DAYS`, paths) are configured via `.env` with compose-level defaults (30-minute warm-up, 24-hour interval, 7-day retention).

Each cycle logs `Database backup OK: <file> (<bytes> bytes)` or `Database backup FAILED` (the same for the data archive where there is one). A failed dump is kept as `<file>.failed` for diagnosis and never overwrites a good backup: grep the log for `FAILED` from your monitoring.

**Verify backups are running:**

```bash
docker compose -p zabbix logs backups | tail -5
docker compose -p zabbix exec backups ls -la /srv/zabbix-postgres/backups/
```

**Restore** with the interactive script (lists backups, prompts for selection, stops the server, drops + recreates + restores the database, starts the server):

```bash
chmod +x zabbix-restore-database.sh
./zabbix-restore-database.sh
```

## Resource limits

Every service carries memory and CPU limits plus reservations as compose-level defaults: the same values CI boots the stack under. Override any of them in `.env` (the knobs and their defaults are listed in `.env.example`, e.g. `TRAEFIK_MEMORY_LIMIT=512m`) and the override survives every `git pull`. If a service is OOM-killed under real load, `docker inspect <container> --format '{{.State.OOMKilled}}'` says so; raise its `_MEMORY_LIMIT` and recreate.

## Container hardening

Every service runs with `security_opt: no-new-privileges:true`, so a process cannot gain privileges through setuid binaries even if it escapes its initial capability set. Infrastructure containers (the reverse proxy, databases, caches, backups) run with `cap_drop: [ALL]` and add back only what their entrypoints need: `NET_BIND_SERVICE` for Traefik to bind :80/:443, `CHOWN`/`SETUID`/`SETGID` (and friends) for database images to own their data directory and drop to their service user. Application containers keep the default capability set on purpose: upstream images assume it, and a wrong guess there is a boot loop in production rather than a hardening win. CI boots the stack under exactly these settings on every push, so what ships is what was tested.

## Testing

The [Deployment Verification](https://github.com/heyvaldemar/zabbix-traefik-letsencrypt-docker-compose/actions/workflows/deployment-verification.yml?query=branch%3Amain) workflow runs on every push, pull request, and every day at 06:00 UTC:

1. **Lint**: shellcheck on the restore script, actionlint on the workflow.
2. **Trivy scans** of all five pinned images (CRITICAL/HIGH, SARIF to the Security tab).
3. **Pin freshness** (daily/manual): digest drift, LTS-line currency via endoflife.date, Traefik release lag.
4. **Deploy-and-test**: boots the full stack with ephemeral credentials, waits for the zabbix-server healthcheck, then requires the web API (`apiinfo.version`) to answer through Traefik. The shipped configuration must produce a working Zabbix, not just started containers.

A green run is the authoritative proof that the template deploys end-to-end and that its backups restore.

### Backup and restore, proven

`tests/e2e-backup-restore.sh` runs against the live stack and is what CI executes after the HTTPS smoke. The scenario that matters most is the restore roundtrip: insert a marker row, restore the earliest backup, assert the marker is gone. A backup that cannot be restored fails the build. Run it yourself against a running deployment with short intervals in `.env` (`BACKUP_INIT_SLEEP=15s`, `BACKUP_INTERVAL=60s`):

```bash
chmod +x tests/e2e-backup-restore.sh
./tests/e2e-backup-restore.sh
```

It stops the database container briefly to prove failure detection: run it on a staging copy, not on production.

## Security notes

- Credentials are read from `.env` at deploy time; `.env` is gitignored and compose fails fast on missing required variables.
- **Pre-rotation advisory.** Releases before v1.0.0 (2026-08-31) shipped a tracked `.env` with a generated-looking database password. Rotate `ZABBIX_DB_PASSWORD` if your deployment reused it.
- The database listens only on the internal network; only 80/443/10051 are exposed through Traefik.
- Upstream image digests are pinned; the daily freshness job flags drift loudly.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
