# Proxy Fleet Control — Design Spec

**Date:** 2026-09-27  
**Status:** Approved for implementation planning  
**Workspace:** `keep-cpa-otd`

## Goal

Provide a GitHub-clonable toolkit so a cloud Linux server can:

1. One-command **deploy** and **undeploy** a small fleet of API proxy services.
2. **Per-service** and **all-services** start / stop / restart / update / status.
3. Stay on **latest upstream source** via `git pull` + local Docker build.
4. Run **scheduled updates** twice daily (America/New_York 07:00 and 00:00).
5. Scale to add/remove services later without rewriting the CLI.

Initial services:

- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
- [commandcode-proxy](https://github.com/MAXeaglet/commandcode-proxy)

## Non-goals (v1)

- Web UI / remote dashboard.
- Multi-host orchestration (Kubernetes, etc.).
- Automatic config migration when upstream changes config schema.
- Purging git clones on undeploy by default.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Runtime | Docker Compose (Docker already on server) |
| Update source | Git clone + local `docker build` (track latest commits) |
| Layout | Toolkit repo separate from service clones under `TOOLS_DIR` |
| Auto-update | Included in v1; `deploy` installs timer |
| Extensibility | Per-service YAML registry under `services/` |

## Layout

### Toolkit repo (`keep-cpa-otd`)

```text
keep-cpa-otd/
├── proxyctl                          # Single CLI entrypoint (bash)
├── lib/                              # Shared helpers
│   ├── common.sh
│   ├── compose.sh                    # Generate compose from registry
│   ├── git.sh
│   ├── docker.sh
│   └── timer.sh
├── services/                         # One YAML per service
│   ├── cliproxyapi.yaml
│   └── commandcode-proxy.yaml
├── templates/
│   └── compose.service.fragment.yml  # Optional fragment helpers
├── config.example.yaml
├── config.yaml                       # Local/server overrides (gitignored)
├── runtime/                          # Generated; gitignored
│   ├── docker-compose.yml
│   ├── update.log
│   └── state/                        # e.g. last update SHA timestamps
├── docs/superpowers/specs/
└── README.md
```

### Server layout after deploy

```text
~/tools/                    # TOOLS_DIR (configurable)
├── keep-cpa-otd/           # This toolkit (cloned from GitHub)
├── CLIProxyAPI/            # Independent git clone
└── commandcode-proxy/
```

Rules:

- Toolkit owns orchestration only; it does not vendor upstream source trees.
- Runtime artifacts (`runtime/`) stay on the server and are not committed.
- Secrets and machine-specific env files stay outside git (paths referenced from service YAML / `config.yaml`).

## Configuration

### `config.yaml` (from `config.example.yaml`)

```yaml
tools_dir: ~/tools
timezone: America/New_York
update_cron:
  - "0 7 * * *"    # 07:00
  - "0 0 * * *"    # 00:00
compose_project_name: keep-cpa-otd
```

Paths in service YAML may use `${TOOLS_DIR}` expanded from `tools_dir`.

### Service registry schema (`services/<name>.yaml`)

```yaml
name: cliproxyapi
repo: https://github.com/router-for-me/CLIProxyAPI.git
branch: main
dir: CLIProxyAPI                 # relative to TOOLS_DIR

build:
  context: .                     # relative to that git dir
  dockerfile: Dockerfile

ports:
  - "8317:8317"

volumes:
  - "${TOOLS_DIR}/CLIProxyAPI/config.yaml:/CLIProxyAPI/config.yaml"
  - "${TOOLS_DIR}/CLIProxyAPI/auths:/root/.cli-proxy-api"
  - "${TOOLS_DIR}/CLIProxyAPI/logs:/CLIProxyAPI/logs"

env_file: null                   # or absolute/relative path to a local .env
restart: unless-stopped
enabled: true                    # false => registered but excluded from "all"
```

`commandcode-proxy` uses the same schema with its own repo, ports, and volumes.

Adding a service: add `services/<name>.yaml`, then `./proxyctl deploy <name>` (or `deploy`).  
Retiring a service: `./proxyctl undeploy <name>`, then optionally delete the YAML.

## CLI

Entrypoint: `./proxyctl <command> [service|all] [flags]`

| Command | Behavior |
|---------|----------|
| `deploy [name\|all]` | Ensure clone exists → regenerate compose → build → `up -d` → install/refresh timer (on `all` or first deploy) |
| `undeploy [name\|all]` | Stop and remove containers for target; on `all`, also remove timer. Does **not** delete git dirs or config/auth by default |
| `undeploy --purge [name\|all]` | Same as undeploy, plus delete the service git directory under `TOOLS_DIR` |
| `start / stop / restart [name\|all]` | Lifecycle via Docker Compose |
| `status [name\|all]` | Show running state, container id, git short SHA, last update time |
| `update [name\|all]` | Git pull; build + recreate only if commit changed |
| `logs <name> [-f]` | Container logs; **name required** (no `all`) |
| `enable-timer` / `disable-timer` | Install/remove scheduled `update all` |

Defaults:

- Missing service argument means `all`, except `logs`.
- Unknown service name: error and list registered names from `services/*.yaml`.
- Only `enabled: true` services participate in `all`.

## Compose generation

On deploy/update paths that need it:

1. Scan `services/*.yaml` for `enabled: true` (or the named service).
2. Emit `runtime/docker-compose.yml` with one Compose service per registry entry.
3. Build context is `${TOOLS_DIR}/${dir}` with the configured Dockerfile.
4. All Docker operations use `docker compose -f runtime/docker-compose.yml -p <compose_project_name>`.

## Update flow (per service)

1. Record `OLD_SHA` (`git rev-parse HEAD`).
2. `git fetch --prune` and `git pull --ff-only` on configured branch.
3. If working tree is dirty in a way that blocks ff-only: fail, log, do not force-reset (unless a future explicit flag is added).
4. If `NEW_SHA == OLD_SHA`: log skip; exit 0 for that service.
5. Else: `docker compose build <name>` then `up -d --force-recreate <name>`.
6. Health check (v1): container is running via `docker compose ps` / inspect.
7. Append result to `runtime/update.log` and record timestamp/SHA under `runtime/state/`.

### Failure rollback (v1)

- If build or recreate fails after a SHA change: `git reset --hard OLD_SHA`, rebuild and recreate previous image/code.
- If rollback also fails: leave the service in failed/stopped state, non-zero exit (so timers/cron can surface failure). Do not silently swallow errors.

`update all` runs services sequentially; one failure should not skip the remaining services, but the overall exit code is non-zero if any failed.

## Scheduling

- Schedule: America/New_York at 07:00 and 00:00 (DST-aware via timezone, not fixed UTC offsets).
- v1 implementation: **user crontab** entries with `TZ=America/New_York` invoking `proxyctl update all` (absolute path to the toolkit). This avoids `loginctl enable-linger` requirements that systemd user timers have on headless servers.
- `deploy all` installs or refreshes the crontab entries; deploying a single service does not.
- `undeploy all` and `disable-timer` remove those entries.
- Crontab always calls the same `update` path as manual updates.

## Deploy / undeploy semantics

### `deploy`

1. Load `config.yaml` (create from example if missing, with safe defaults).
2. Ensure `TOOLS_DIR` exists.
3. For each target service: clone if missing; checkout branch.
4. Regenerate compose file.
5. Build and `up -d` target services.
6. When the target is `all`, install or refresh the update timer. Deploying a single named service does not change the timer. Use `enable-timer` / `disable-timer` to manage it explicitly.

### `undeploy`

1. `docker compose stop` + `rm` for target services.
2. If `all`: disable timer; optionally remove generated compose project.
3. Without `--purge`: leave git clones, configs, auths, logs intact.
4. With `--purge`: delete `${TOOLS_DIR}/${dir}` for target services.

## Observability (v1)

- `status`: human-readable table (name, state, sha, last update).
- `logs <name> [-f]`: `docker compose logs`.
- `runtime/update.log`: append-only update history for timer and manual runs.

No metrics stack in v1.

## Security / secrets

- Do not commit API keys, `config.yaml` machine secrets, or auth directories.
- Service YAML may reference host paths for config/auth; those files are operator-managed on the server.
- README must document required host prep (e.g. create `config.yaml` / auth dirs before first successful start).

## Testing (implementation phase)

- Dry-run/unit-style checks for YAML loading and compose generation (no Docker required).
- Manual verification checklist on a server: deploy → status → stop one → start one → update skip → update with forced SHA bump simulation → undeploy → timer enable/disable.

## Open points resolved in this spec

- Process manager: Docker Compose (not bare systemd for app processes).
- Source of truth for code: git under `TOOLS_DIR`, not only published images.
- Toolkit vs app repos: separate clones; toolkit does not use submodules.
- Auto-update: in v1, installed by deploy.
