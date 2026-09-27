# keep-cpa-otd

Bash toolkit to deploy and operate a small fleet of API proxy services (CLIProxyAPI, commandcode-proxy) on a Linux server with Docker Compose. Design details: `docs/superpowers/specs/2026-09-27-proxy-fleet-ctl-design.md`.

## Prerequisites

Install on the server before using `proxyctl`:

| Tool | Purpose |
|------|---------|
| **Docker Compose v2** (`docker compose`) | Build and run service containers |
| **git** | Clone upstream repos and pull updates |
| **yq** | Parse service registry YAML ([mikefarah/yq](https://github.com/mikefarah/yq) v4+) |
| **bash** | Run `proxyctl` and library scripts |

Install **yq** if missing, for example: `sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq` (pick the binary for your architecture from the release page).

Docker Engine must be installed and the operator user able to run `docker` (group membership or root).

## Server layout

After setup, paths under `~/tools` (or your configured `tools_dir`) look like:

```text
~/tools/
├── keep-cpa-otd/           # This toolkit (clone of this repo)
├── CLIProxyAPI/            # Upstream git clone (created by deploy)
└── commandcode-proxy/      # Upstream git clone (created by deploy)
```

Generated files stay inside the toolkit:

```text
~/tools/keep-cpa-otd/runtime/
├── docker-compose.yml      # Generated from services/*.yaml
├── cron.log                # Scheduled update output
├── update.log              # Update history
└── state/                  # Last successful update per service
```

`config.yaml` is local to the server and is not committed.

## Clone and configure

1. Create the tools directory and clone the toolkit:

   ```bash
   mkdir -p ~/tools
   cd ~/tools
   git clone <your-fork-or-origin-url> keep-cpa-otd
   cd keep-cpa-otd
   ```

2. Copy configuration:

   ```bash
   cp config.example.yaml config.yaml
   ```

3. Edit `config.yaml` if needed. Defaults:

   - `tools_dir: ~/tools`
   - `timezone: America/New_York`
   - `compose_project_name: keep-cpa-otd`

4. Deploy the fleet (clones upstream repos, builds images, starts containers, installs the update timer):

   ```bash
   ./proxyctl deploy
   ```

## Host prep before first deploy

### CLIProxyAPI

`deploy` creates host directories for volume mounts and seeds `~/tools/CLIProxyAPI/config.yaml` from the upstream repo’s `config.example.yaml` when missing. You still need to:

- Review and edit `~/tools/CLIProxyAPI/config.yaml` for your environment. Keep `auth-dir` as `~/.cli-proxy-api` (in the container that is `/root/.cli-proxy-api`).
- OAuth tokens are persisted on the host under `~/tools/CLIProxyAPI/auths/` via the bind mount to `/root/.cli-proxy-api`. **Log in inside the container** after deploy (you do not need to OAuth on the host first); files appear under `auths/` on the host automatically.
- Optional: use `~/tools/CLIProxyAPI/logs/` and `~/tools/CLIProxyAPI/plugins/` as configured in `services/cliproxyapi.yaml`.
- Optional API keys: put a host `.env` (for example `~/tools/CLIProxyAPI/.env`) and set `env_file` in `services/cliproxyapi.yaml`.

See the [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) README for config and auth details.

### commandcode-proxy

The registry uses port `3050` and no host volume mounts by default. Depending on your upstream version, you may need environment variables or auth files—follow the [commandcode-proxy](https://github.com/MAXeaglet/commandcode-proxy) README. To use an env file, set `env_file` in `services/commandcode-proxy.yaml` to a path on the server (outside git).

## Command cheat sheet

```text
Usage: proxyctl <command> [service|all] [flags]

Commands:
  deploy [--] [name|all]     Clone/build/start; install timer if all
  undeploy [--purge] [name|all]
  start|stop|restart [name|all]
  status [name|all]
  update [name|all]
  logs <name> [-f]
  enable-timer | disable-timer
  help
```

| Command | Behavior |
|---------|----------|
| `deploy [name\|all]` | Ensure clone → regenerate compose → build → `up -d`. **`deploy all`** also installs/refreshes the update timer. |
| `undeploy [name\|all]` | Stop and remove containers. **`undeploy all`** removes the timer. Does not delete git dirs or config by default. |
| `undeploy --purge [name\|all]` | Same as undeploy, plus delete the service directory under `tools_dir`. |
| `start` / `stop` / `restart` | Container lifecycle via Docker Compose. |
| `status` | Table: name, state, container id, git short SHA, last update time. |
| `update` | `git pull`; rebuild and recreate only if the commit changed (logs “no update” when unchanged). |
| `logs <name> [-f]` | Service logs; **service name required** (no `all`). |
| `enable-timer` / `disable-timer` | Add or remove crontab entries for scheduled updates. |

Defaults: omitting the service name means **`all`** (except `logs`). Only services with `enabled: true` in `services/*.yaml` are included in `all`.

## Adding a service

1. Add `services/<name>.yaml` using the same schema as existing entries (`name`, `repo`, `branch`, `dir`, `build`, `ports`, `volumes`, `enabled`, etc.).
2. Run:

   ```bash
   ./proxyctl deploy <name>
   ```

   Or redeploy everything with `./proxyctl deploy`.

## Removing a service

1. Stop and remove containers:

   ```bash
   ./proxyctl undeploy <name>
   ```

   Use `./proxyctl undeploy --purge <name>` to delete the upstream clone under `tools_dir`.

2. Delete `services/<name>.yaml` from the toolkit repo when you no longer want it registered.

## Scheduled updates

`deploy all` installs a **user crontab** block that runs:

```bash
<toolkit>/proxyctl update all
```

Schedules (from `config.yaml`, interpreted in **`America/New_York`**):

- **07:00** daily (`0 7 * * *`)
- **00:00** daily (`0 0 * * *`)

Crontab lines include `TZ=America/New_York` so local time follows DST. Output is appended to `runtime/cron.log`. Deploying a **single** service does not change the timer; use `enable-timer` / `disable-timer` or `undeploy all` to manage it.

## Manual verification checklist

Run on a server after changes or for onboarding. Check each step succeeds.

```text
[ ] ./proxyctl deploy
[ ] ./proxyctl status
[ ] ./proxyctl stop commandcode-proxy && ./proxyctl status
[ ] ./proxyctl start commandcode-proxy
[ ] ./proxyctl update   # expect skip if no upstream change
[ ] ./proxyctl undeploy commandcode-proxy
[ ] ./proxyctl deploy commandcode-proxy
[ ] ./proxyctl disable-timer && ./proxyctl enable-timer
[ ] ./proxyctl undeploy all
```

## Development

Run tests from the repo root:

```bash
./tests/run.sh
```
