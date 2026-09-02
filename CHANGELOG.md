# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.1.0] - 2026-09-02

### Fixed

- **A failed database dump no longer produces a silent, corrupt backup.**
  The old loop piped the dump into `gzip` and only checked `gzip`'s exit
  status, so a dump that failed halfway (database down, wrong password,
  disk full) still left a small `.gz` that looked like a backup. The loop
  now runs with `pipefail`, logs `Database backup OK: <file> (<bytes>
  bytes)` or `Database backup FAILED` per cycle, keeps a failed dump as
  `<file>.failed` for diagnosis, and prunes only its own files. Retention
  set to `0` disables pruning instead of deleting everything.

### Added

- CI now waits for the first backup cycle and proves the produced
  archive is readable and contains a real dump header (plus a readable
  `tar.gz` for the data backup where the stack has one).

## [1.0.0] - 2026-08-31

First semver release. Brings this template to the fleet standard established
in [keycloak-traefik-letsencrypt-docker-compose](https://github.com/heyvaldemar/keycloak-traefik-letsencrypt-docker-compose)
v1.2.0.

### Security

- **Credentials untracked from git.** The repository previously shipped a
  tracked `.env` with a generated-looking database password; anyone who
  deployed without editing it ran production on credentials published on
  GitHub. `.env` is now gitignored; `.env.example` ships `change_me_*`
  placeholders with generation commands, and the compose file fails fast
  via `${VAR:?}` when required secrets are unset.
- **Zabbix bumped 6.4.6 → 7.0.30 LTS** (server, web, and agent2 images move
  together). The 6.4 line has been end-of-life since 2024-12-31; 7.0 is the
  LTS line supported until 2029. The server migrates the database schema
  automatically on first start — back up before pulling.
- **Traefik bumped 3.2 → 3.7** (`traefik:3.7@sha256:9c2a54d8…`). Traefik
  3.2's vendored Docker client cannot talk to Docker Engine 29 — the docker
  provider fails in a retry loop and the stack silently serves 404s on
  hosts running current Docker.
- **All five images pinned by `tag@sha256:digest`** (`postgres:15`
  digest-pinned; PostgreSQL major deliberately unchanged so existing data
  directories keep working).

### Changed

- **Image pins live in the compose file as interpolation defaults**
  (`x-images` block): `git pull` alone delivers the tested version
  combination, `.env` carries only secrets and deliberate overrides, and
  an override set in `.env` still wins.
- Operational variables (log level, timezone, DB names, cache size, backup
  schedule and paths) now have compose-level defaults — the minimal `.env`
  is secrets and hostnames only.
- Backup-loop variables escaped (`$$VAR`) so the container shell resolves
  them at runtime from the `environment:` block, where the compose-level
  defaults live.

### Added

- **Deployment Verification workflow** rebuilt: shellcheck + actionlint
  lint job; Trivy scans of all five pinned images (SARIF to the Security
  tab); weekly `check-pin-freshness` job that re-resolves every pinned tag
  against its registry, compares the pinned Zabbix version against the
  latest patch of its LTS line via endoflife.date (failing loudly if the
  line itself goes EOL), and checks the Traefik minor against the latest
  upstream release; and a deploy-and-test job that stands up the full
  stack with ephemeral credentials, waits for the zabbix-server
  healthcheck, and requires the web API (`apiinfo.version`) to answer
  through Traefik — the shipped configuration must produce a working
  Zabbix instance, not just started containers.

### Fixed

- Shellcheck findings in the restore script (`read -r`, removed an unused
  unquoted variable).

[Unreleased]: https://github.com/heyvaldemar/zabbix-traefik-letsencrypt-docker-compose/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/heyvaldemar/zabbix-traefik-letsencrypt-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/zabbix-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
