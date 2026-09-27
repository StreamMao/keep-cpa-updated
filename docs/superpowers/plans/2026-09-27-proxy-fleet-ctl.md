# Proxy Fleet Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a GitHub-clonable `proxyctl` toolkit that deploys, updates, and manages CLIProxyAPI and commandcode-proxy (and future services) via Docker Compose with twice-daily America/New_York auto-updates.

**Architecture:** Per-service YAML registry under `services/` drives generated `runtime/docker-compose.yml`. A single bash CLI (`proxyctl`) clones/pulls repos under configurable `TOOLS_DIR`, builds locally, and wraps Compose lifecycle. Crontab with `TZ=America/New_York` calls `proxyctl update all`.

**Tech Stack:** Bash 4+, Docker Compose v2, `yq` (mikefarah) for YAML, git, user crontab.

## Global Constraints

- Follow spec: `docs/superpowers/specs/2026-09-27-proxy-fleet-ctl-design.md`
- Toolkit does not vendor upstream source; clones live under `TOOLS_DIR`
- Missing service arg defaults to `all` except `logs` (name required)
- Only `enabled: true` services participate in `all`
- `undeploy` does not delete git dirs unless `--purge`
- `deploy all` installs/refreshes crontab; single-service deploy does not
- Update: skip rebuild if SHA unchanged; on build/recreate failure after SHA change, `git reset --hard OLD_SHA` then rebuild/recreate
- `update all`: continue remaining services after one failure; overall exit non-zero if any failed
- Do not commit secrets, `config.yaml`, or `runtime/`
- Code, comments, and commit messages in English; user-facing README may include Chinese section if helpful, but primary README in English with clear server ops steps

## File Structure

| Path | Responsibility |
|------|----------------|
| `proxyctl` | CLI dispatch only |
| `lib/common.sh` | ROOT, config load, logging, deps, path expand |
| `lib/registry.sh` | List/load service YAML via yq |
| `lib/compose.sh` | Generate `runtime/docker-compose.yml` |
| `lib/git.sh` | Clone, pull ff-only, SHA helpers |
| `lib/docker.sh` | Compose wrappers: build/up/stop/rm/ps/logs |
| `lib/timer.sh` | Crontab install/remove with markers |
| `lib/cmd_*.sh` or logic inside `proxyctl` | Command implementations (prefer functions in lib files called from proxyctl) |
| `services/*.yaml` | Service registry |
| `config.example.yaml` | Default config template |
| `tests/helpers.sh` | Assert helpers |
| `tests/test_*.sh` | Unit tests (no Docker required where possible) |
| `tests/run.sh` | Test runner |
| `.gitignore` | Ignore `config.yaml`, `runtime/`, secrets |
| `README.md` | Server usage |

Suggested command function layout (keep proxyctl thin):

- `lib/commands.sh` — `cmd_deploy`, `cmd_undeploy`, `cmd_start`, `cmd_stop`, `cmd_restart`, `cmd_status`, `cmd_update`, `cmd_logs`, `cmd_enable_timer`, `cmd_disable_timer`

---

### Task 1: Scaffold + test harness

**Files:**
- Create: `.gitignore`
- Create: `config.example.yaml`
- Create: `tests/helpers.sh`
- Create: `tests/run.sh`
- Create: `tests/test_scaffold.sh`
- Create: `README.md` (minimal stub pointing to later docs)

**Interfaces:**
- Produces: `tests/run.sh` exits 0 when all `tests/test_*.sh` pass; helpers `assert_eq`, `assert_file_exists`, `assert_contains`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
config.yaml
runtime/
*.log
.env
**/.env
```

- [ ] **Step 2: Create `config.example.yaml`**

```yaml
tools_dir: ~/tools
timezone: America/New_York
update_cron:
  - "0 7 * * *"
  - "0 0 * * *"
compose_project_name: keep-cpa-updated
```

- [ ] **Step 3: Create test helpers and runner**

`tests/helpers.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ASSERT_FAILS=0

assert_eq() {
  local want="$1" got="$2" msg="${3:-}"
  if [[ "$want" != "$got" ]]; then
    echo "FAIL assert_eq ${msg}: want=[$want] got=[$got]" >&2
    ASSERT_FAILS=$((ASSERT_FAILS + 1))
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL assert_file_exists: $path" >&2
    ASSERT_FAILS=$((ASSERT_FAILS + 1))
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL assert_contains ${msg}: missing [$needle]" >&2
    ASSERT_FAILS=$((ASSERT_FAILS + 1))
  fi
}

finish_asserts() {
  if [[ "$ASSERT_FAILS" -ne 0 ]]; then
    echo "FAILED with $ASSERT_FAILS assertion(s)" >&2
    exit 1
  fi
  echo "OK"
}
```

`tests/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
for t in "$ROOT"/tests/test_*.sh; do
  echo "==> $(basename "$t")"
  if ! bash "$t"; then
    fail=1
  fi
done
exit "$fail"
```

`tests/test_scaffold.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=helpers.sh
source "$ROOT/tests/helpers.sh"
assert_file_exists "$ROOT/config.example.yaml"
assert_file_exists "$ROOT/.gitignore"
finish_asserts
```

- [ ] **Step 4: Minimal README stub**

```markdown
# keep-cpa-updated

Proxy fleet control for CLIProxyAPI and commandcode-proxy. See `docs/superpowers/specs/2026-09-27-proxy-fleet-ctl-design.md`.

Usage docs will land when `proxyctl` is implemented.
```

- [ ] **Step 5: Run tests**

Run: `chmod +x tests/run.sh tests/test_scaffold.sh && bash tests/run.sh`  
Expected: `OK` and exit 0

- [ ] **Step 6: Commit**

```bash
git add .gitignore config.example.yaml tests README.md
git commit -m "chore: scaffold config, gitignore, and test harness"
```

---

### Task 2: `lib/common.sh` — paths, config, logging, dependencies

**Files:**
- Create: `lib/common.sh`
- Create: `tests/test_common.sh`
- Modify: none

**Interfaces:**
- Produces:
  - `ROOT_DIR` — absolute path to toolkit root
  - `load_config` — reads `config.yaml` or copies from example; sets `TOOLS_DIR`, `TIMEZONE`, `COMPOSE_PROJECT_NAME`, `UPDATE_CRON` (newline-separated cron exprs)
  - `expand_path path` — expands `~`
  - `log_info` / `log_error` / `log_update` — stdout/stderr and append to `runtime/update.log`
  - `require_cmds` — verifies `docker`, `git`, `yq` exist
  - `ensure_runtime_dirs` — creates `runtime/` and `runtime/state/`

- [ ] **Step 1: Write failing test `tests/test_common.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
# Point ROOT_DIR override if common allows; otherwise copy toolkit bits into TMP
# Preferred: common.sh uses BASH_SOURCE to find ROOT_DIR relative to lib/

# After implementation: create isolated config
mkdir -p "$TMP/kit"
cp "$ROOT/config.example.yaml" "$TMP/kit/config.yaml"
# If load_config is bound to ROOT_DIR, set ROOT_DIR via sourcing pattern documented in common.sh

# Minimal contract for this task: expand_path and require_cmds / load from a file
got="$(expand_path '~/tools')"
assert_eq "$TMP/tools" "$got" "expand_path tilde"

finish_asserts
```

Adjust the test after `common.sh` sets `ROOT_DIR` from `BASH_SOURCE`; for `load_config`, either:

- accept optional path argument `load_config [file]`, or
- run with `ROOT_DIR` exported before source.

**Preferred API for testability:**

```bash
# lib/common.sh
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
load_config() {
  local cfg="${1:-$ROOT_DIR/config.yaml}"
  ...
}
```

Update `tests/test_common.sh` to:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"

got="$(expand_path '~/tools')"
assert_eq "$HOME/tools" "$got" "expand_path"

CFG="$TMP/config.yaml"
cp "$ROOT/config.example.yaml" "$CFG"
load_config "$CFG"
assert_eq "keep-cpa-updated" "$COMPOSE_PROJECT_NAME" "project name"
assert_eq "$HOME/tools" "$TOOLS_DIR" "tools_dir expanded"
assert_contains "$UPDATE_CRON" "0 7 * * *" "cron morning"

finish_asserts
```

- [ ] **Step 2: Run test — expect FAIL (missing common.sh)**

Run: `bash tests/test_common.sh`  
Expected: FAIL (source error or missing function)

- [ ] **Step 3: Implement `lib/common.sh`**

```bash
#!/usr/bin/env bash
# shellcheck shell=bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

expand_path() {
  local p="$1"
  if [[ "$p" == ~* ]]; then
    p="${p/#\~/$HOME}"
  fi
  echo "$p"
}

log_info()  { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

log_update() {
  mkdir -p "$ROOT_DIR/runtime"
  local line="[$(date '+%F %T %Z')] $*"
  echo "$line" | tee -a "$ROOT_DIR/runtime/update.log"
}

require_cmds() {
  local missing=0
  local c
  for c in docker git yq; do
    if ! command -v "$c" >/dev/null 2>&1; then
      log_error "Missing required command: $c"
      missing=1
    fi
  done
  if ! docker compose version >/dev/null 2>&1; then
    log_error "docker compose (v2) is required"
    missing=1
  fi
  return "$missing"
}

ensure_runtime_dirs() {
  mkdir -p "$ROOT_DIR/runtime/state"
}

load_config() {
  local cfg="${1:-$ROOT_DIR/config.yaml}"
  if [[ ! -f "$cfg" ]]; then
    if [[ -f "$ROOT_DIR/config.example.yaml" ]]; then
      cp "$ROOT_DIR/config.example.yaml" "$cfg"
      log_info "Created $cfg from config.example.yaml"
    else
      log_error "No config at $cfg"
      return 1
    fi
  fi
  TOOLS_DIR="$(expand_path "$(yq -r '.tools_dir' "$cfg")")"
  TIMEZONE="$(yq -r '.timezone' "$cfg")"
  COMPOSE_PROJECT_NAME="$(yq -r '.compose_project_name' "$cfg")"
  UPDATE_CRON="$(yq -r '.update_cron[]' "$cfg")"
  export TOOLS_DIR TIMEZONE COMPOSE_PROJECT_NAME UPDATE_CRON
}
```

Note: `require_cmds` returns 1 if missing; callers should `require_cmds || exit 1`. Fix the return to use `[[ $missing -eq 0 ]]` properly:

```bash
  [[ "$missing" -eq 0 ]]
}
```

- [ ] **Step 4: Run test**

Run: `bash tests/test_common.sh`  
Expected: `OK` (requires `yq` installed on the machine running tests)

If `yq` missing in CI/dev: document install `sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq` in README; tests may skip `load_config` only if yq absent — prefer requiring yq.

- [ ] **Step 5: Commit**

```bash
git add lib/common.sh tests/test_common.sh
git commit -m "feat: add common config loading and path helpers"
```

---

### Task 3: Service registry (`lib/registry.sh`)

**Files:**
- Create: `lib/registry.sh`
- Create: `services/cliproxyapi.yaml` (minimal valid for tests; ports can be filled fully in Task 8)
- Create: `services/commandcode-proxy.yaml` (minimal)
- Create: `tests/test_registry.sh`
- Create: `tests/fixtures/disabled-service.yaml` (optional; or toggle in temp dir)

**Interfaces:**
- Consumes: `ROOT_DIR`, `TOOLS_DIR`, `yq`
- Produces:
  - `list_service_files` → paths
  - `list_services [all|enabled]` → names
  - `service_field name key` → string (supports dotted keys via yq)
  - `service_dir name` → absolute `${TOOLS_DIR}/$(dir)`
  - `resolve_targets arg` → newline-separated names (`all` expands to enabled; validates unknown)
  - `service_exists name` → 0/1

- [ ] **Step 1: Create minimal service YAMLs**

`services/cliproxyapi.yaml`:

```yaml
name: cliproxyapi
repo: https://github.com/router-for-me/CLIProxyAPI.git
branch: main
dir: CLIProxyAPI
build:
  context: .
  dockerfile: Dockerfile
ports:
  - "8317:8317"
  - "8085:8085"
  - "1455:1455"
  - "54545:54545"
  - "51121:51121"
  - "11451:11451"
volumes:
  - "${TOOLS_DIR}/CLIProxyAPI/config.yaml:/CLIProxyAPI/config.yaml"
  - "${TOOLS_DIR}/CLIProxyAPI/auths:/root/.cli-proxy-api"
  - "${TOOLS_DIR}/CLIProxyAPI/logs:/CLIProxyAPI/logs"
  - "${TOOLS_DIR}/CLIProxyAPI/plugins:/CLIProxyAPI/plugins"
env_file: null
restart: unless-stopped
enabled: true
```

`services/commandcode-proxy.yaml`:

```yaml
name: commandcode-proxy
repo: https://github.com/MAXeaglet/commandcode-proxy.git
branch: master
dir: commandcode-proxy
build:
  context: .
  dockerfile: Dockerfile
ports:
  - "3050:3050"
volumes: []
environment:
  PORT: "3050"
env_file: null
restart: unless-stopped
enabled: true
```

- [ ] **Step 2: Write failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/registry.sh"
load_config "$ROOT/config.example.yaml"

names="$(list_services enabled | sort | tr '\n' ' ')"
assert_contains "$names" "cliproxyapi" "has cliproxyapi"
assert_contains "$names" "commandcode-proxy" "has commandcode-proxy"

dir="$(service_dir cliproxyapi)"
assert_eq "$TOOLS_DIR/CLIProxyAPI" "$dir" "service_dir"

targets="$(resolve_targets all | wc -l | tr -d ' ')"
assert_eq "2" "$targets" "all => 2"

if resolve_targets nosuch >/dev/null 2>&1; then
  echo "FAIL: unknown service should error" >&2
  ASSERT_FAILS=$((ASSERT_FAILS + 1))
fi

finish_asserts
```

- [ ] **Step 3: Run test — expect FAIL**

Run: `bash tests/test_registry.sh`  
Expected: missing `registry.sh` or functions

- [ ] **Step 4: Implement `lib/registry.sh`**

```bash
#!/usr/bin/env bash

list_service_files() {
  local f
  for f in "$ROOT_DIR"/services/*.yaml; do
    [[ -f "$f" ]] || continue
    echo "$f"
  done
}

service_file_for() {
  local name="$1" f
  for f in $(list_service_files); do
    if [[ "$(yq -r '.name' "$f")" == "$name" ]]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

service_field() {
  local name="$1" key="$2" f
  f="$(service_file_for "$name")" || return 1
  yq -r ".$key" "$f"
}

list_services() {
  local mode="${1:-enabled}" f name en
  for f in $(list_service_files); do
    name="$(yq -r '.name' "$f")"
    en="$(yq -r '.enabled' "$f")"
    if [[ "$mode" == "all" ]] || [[ "$en" == "true" ]]; then
      echo "$name"
    fi
  done
}

service_dir() {
  local name="$1" rel
  rel="$(service_field "$name" dir)"
  echo "$TOOLS_DIR/$rel"
}

resolve_targets() {
  local arg="${1:-all}"
  if [[ "$arg" == "all" ]]; then
    list_services enabled
    return 0
  fi
  if ! service_file_for "$arg" >/dev/null; then
    log_error "Unknown service: $arg"
    log_error "Known: $(list_services all | tr '\n' ' ')"
    return 1
  fi
  echo "$arg"
}
```

- [ ] **Step 5: Run test — expect PASS**

Run: `bash tests/test_registry.sh && bash tests/run.sh`  
Expected: OK

- [ ] **Step 6: Commit**

```bash
git add lib/registry.sh services tests/test_registry.sh
git commit -m "feat: add service registry loading via yq"
```

---

### Task 4: Compose generation (`lib/compose.sh`)

**Files:**
- Create: `lib/compose.sh`
- Create: `tests/test_compose.sh`

**Interfaces:**
- Consumes: registry + `TOOLS_DIR`, `ROOT_DIR`
- Produces: `generate_compose` writes `$ROOT_DIR/runtime/docker-compose.yml`; expands `${TOOLS_DIR}` in volume strings; includes `build.context` as absolute service dir; optional `environment` map; skips `env_file` when null

- [ ] **Step 1: Write failing test**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/compose.sh"
load_config "$ROOT/config.example.yaml"
ensure_runtime_dirs

generate_compose
out="$ROOT_DIR/runtime/docker-compose.yml"
assert_file_exists "$out"
body="$(cat "$out")"
assert_contains "$body" "cliproxyapi:" "service key"
assert_contains "$body" "commandcode-proxy:" "service key"
assert_contains "$body" "dockerfile: Dockerfile" "dockerfile"
assert_contains "$body" "8317:8317" "cliproxy port"
assert_contains "$body" "3050:3050" "cc port"
assert_contains "$body" "$TOOLS_DIR/CLIProxyAPI" "expanded tools dir in volumes"

finish_asserts
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement `generate_compose`**

Generate Compose v2 YAML without obsolete `version:` key. Pseudocode approach using yq to build a document, or emit with a bash heredoc loop:

```bash
generate_compose() {
  ensure_runtime_dirs
  local out="$ROOT_DIR/runtime/docker-compose.yml"
  local tmp
  tmp="$(mktemp)"
  {
    echo "services:"
    local name f ctx df restart ports_json
    for name in $(list_services enabled); do
      f="$(service_file_for "$name")"
      ctx="$(service_dir "$name")/$(yq -r '.build.context' "$f")"
      # normalize context . => service_dir
      if [[ "$(yq -r '.build.context' "$f")" == "." ]]; then
        ctx="$(service_dir "$name")"
      fi
      df="$(yq -r '.build.dockerfile' "$f")"
      restart="$(yq -r '.restart' "$f")"
      echo "  $name:"
      echo "    build:"
      echo "      context: $ctx"
      echo "      dockerfile: $df"
      echo "    restart: $restart"
      echo "    ports:"
      yq -r '.ports[]' "$f" | while read -r p; do
        echo "      - \"$p\""
      done
      # volumes
      local volcount
      volcount="$(yq -r '.volumes | length' "$f")"
      if [[ "$volcount" != "0" && "$volcount" != "null" ]]; then
        echo "    volumes:"
        yq -r '.volumes[]' "$f" | while read -r v; do
          v="${v//\$\{TOOLS_DIR\}/$TOOLS_DIR}"
          echo "      - \"$v\""
        done
      fi
      # environment map if present
      if [[ "$(yq -r '.environment | type' "$f")" == "!!map" ]]; then
        echo "    environment:"
        yq -r '.environment | to_entries[] | "      \(.key): \"\(.value)\""' "$f"
      fi
      # env_file if not null
      local ef
      ef="$(yq -r '.env_file' "$f")"
      if [[ "$ef" != "null" && -n "$ef" ]]; then
        echo "    env_file:"
        echo "      - $(expand_path "$ef")"
      fi
    done
  } >"$tmp"
  mv "$tmp" "$out"
}
```

Implement carefully so nested loops under pipes don't lose variables; prefer process substitution or `mapfile` over `while read` in pipe where needed.

- [ ] **Step 4: Run tests — expect PASS**

Run: `bash tests/test_compose.sh && bash tests/run.sh`

- [ ] **Step 5: Commit**

```bash
git add lib/compose.sh tests/test_compose.sh
git commit -m "feat: generate docker-compose.yml from service registry"
```

---

### Task 5: Git helpers (`lib/git.sh`)

**Files:**
- Create: `lib/git.sh`
- Create: `tests/test_git.sh`

**Interfaces:**
- Produces:
  - `ensure_clone name` — clone if missing; fetch + checkout branch
  - `git_sha name` — full SHA
  - `git_sha_short name`
  - `git_pull_ff name` — fetch + pull --ff-only; returns 0; prints nothing special; on dirty/conflict fails
  - Does not force-clean dirty trees

- [ ] **Step 1: Write test using a temp bare/local repo**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/git.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
TOOLS_DIR="$TMP/tools"
mkdir -p "$TOOLS_DIR" "$ROOT/services-test"
# Create a fake service yaml pointing at a local repo
git init -b main "$TMP/upstream"
git -C "$TMP/upstream" config user.email t@t
git -C "$TMP/upstream" config user.name t
echo hi >"$TMP/upstream/README"
git -C "$TMP/upstream" add README
git -C "$TMP/upstream" commit -m init

# Override ROOT_DIR services for this test by writing to a temp kit copy OR
# add ensure_clone_at(repo,branch,dir) lower-level API for testability.

# Preferred lower-level API:
# ensure_repo "$repo" "$branch" "$dest"
ensure_repo "$TMP/upstream" "main" "$TOOLS_DIR/fake"
assert_file_exists "$TOOLS_DIR/fake/README"
sha1="$(git -C "$TOOLS_DIR/fake" rev-parse HEAD)"
echo bye >>"$TMP/upstream/README"
git -C "$TMP/upstream" commit -am next
git_pull_ff_repo "$TOOLS_DIR/fake"
sha2="$(git -C "$TOOLS_DIR/fake" rev-parse HEAD)"
[[ "$sha1" != "$sha2" ]] || { echo FAIL no pull; exit 1; }

finish_asserts
```

Expose both:

- `ensure_repo repo branch dest`
- `ensure_clone name` → looks up registry fields then calls `ensure_repo`
- `git_pull_ff_repo dest` / `git_pull_ff name`

- [ ] **Step 2: Implement**

```bash
ensure_repo() {
  local repo="$1" branch="$2" dest="$3"
  if [[ ! -d "$dest/.git" ]]; then
    mkdir -p "$(dirname "$dest")"
    git clone --branch "$branch" "$repo" "$dest"
  else
    git -C "$dest" fetch --prune origin
    git -C "$dest" checkout "$branch"
  fi
}

ensure_clone() {
  local name="$1"
  ensure_repo "$(service_field "$name" repo)" "$(service_field "$name" branch)" "$(service_dir "$name")"
}

git_sha() { git -C "$(service_dir "$1")" rev-parse HEAD; }
git_sha_short() { git -C "$(service_dir "$1")" rev-parse --short HEAD; }

git_pull_ff_repo() {
  local dest="$1"
  git -C "$dest" fetch --prune origin
  git -C "$dest" pull --ff-only
}

git_pull_ff() {
  git_pull_ff_repo "$(service_dir "$1")"
}
```

- [ ] **Step 3: Run tests — PASS**

- [ ] **Step 4: Commit**

```bash
git add lib/git.sh tests/test_git.sh
git commit -m "feat: add git clone and ff-only pull helpers"
```

---

### Task 6: Docker helpers (`lib/docker.sh`)

**Files:**
- Create: `lib/docker.sh`
- Create: `tests/test_docker.sh` (unit-style: verify compose command construction with a dry-run mode)

**Interfaces:**
- Produces:
  - `compose_cmd` → echoes base: `docker compose -f "$ROOT_DIR/runtime/docker-compose.yml" -p "$COMPOSE_PROJECT_NAME"`
  - `compose_build names...`
  - `compose_up names...` — `up -d`
  - `compose_recreate names...` — `up -d --force-recreate --build` or build then up --force-recreate
  - `compose_stop` / `compose_rm` / `compose_restart`
  - `compose_ps` / `compose_logs name [-f]`
  - `container_running name` → 0 if running

For tests without Docker daemon: set `PROXYCTL_DOCKER_DRY_RUN=1` so wrappers print the command and return 0.

- [ ] **Step 1: Write test**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/docker.sh"
load_config "$ROOT/config.example.yaml"
export PROXYCTL_DOCKER_DRY_RUN=1
out="$(compose_build cliproxyapi)"
assert_contains "$out" "docker compose" "prefix"
assert_contains "$out" "build" "build"
assert_contains "$out" "cliproxyapi" "service"
finish_asserts
```

- [ ] **Step 2: Implement with dry-run support**

```bash
compose_cmd() {
  echo docker compose -f "$ROOT_DIR/runtime/docker-compose.yml" -p "$COMPOSE_PROJECT_NAME"
}

_run_compose() {
  local -a cmd
  # shellcheck disable=SC2207
  cmd=($(compose_cmd) "$@")
  if [[ "${PROXYCTL_DOCKER_DRY_RUN:-0}" == "1" ]]; then
    echo "${cmd[*]}"
    return 0
  fi
  "${cmd[@]}"
}

compose_build() { _run_compose build "$@"; }
compose_up() { _run_compose up -d "$@"; }
compose_recreate() { _run_compose up -d --force-recreate "$@"; }
compose_stop() { _run_compose stop "$@"; }
compose_rm() { _run_compose rm -f "$@"; }
compose_restart() { _run_compose restart "$@"; }
compose_logs() { _run_compose logs "$@"; }

container_running() {
  local name="$1" id
  if [[ "${PROXYCTL_DOCKER_DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi
  id="$(_run_compose ps -q "$name" || true)"
  [[ -n "$id" ]] || return 1
  [[ "$(docker inspect -f '{{.State.Running}}' "$id")" == "true" ]]
}
```

- [ ] **Step 3: Run tests — PASS; commit**

```bash
git add lib/docker.sh tests/test_docker.sh
git commit -m "feat: add docker compose wrappers with dry-run"
```

---

### Task 7: Timer / crontab (`lib/timer.sh`)

**Files:**
- Create: `lib/timer.sh`
- Create: `tests/test_timer.sh`

**Interfaces:**
- Consumes: `UPDATE_CRON`, `TIMEZONE`, `ROOT_DIR`
- Produces:
  - `enable_timer` — installs marked crontab block
  - `disable_timer` — removes marked block
  - `timer_installed` → 0/1
- Marker lines: `# BEGIN KEEP-CPA-OTD` / `# END KEEP-CPA-OTD`
- Each cron line: `TZ=America/New_York` is set once (crontab supports `TZ=` env line) then schedule lines calling `"$ROOT_DIR/proxyctl" update all >>"$ROOT_DIR/runtime/cron.log" 2>&1`

Crontab fragment example:

```cron
# BEGIN KEEP-CPA-OTD
TZ=America/New_York
0 7 * * * /abs/path/proxyctl update all >>/abs/path/runtime/cron.log 2>&1
0 0 * * * /abs/path/proxyctl update all >>/abs/path/runtime/cron.log 2>&1
# END KEEP-CPA-OTD
```

For tests: mock `crontab` via `PROXYCTL_CRONTAB_FILE=$TMP/cron` so read/write that file instead of real crontab.

- [ ] **Step 1: Test enable/disable against mock file**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/timer.sh"
load_config "$ROOT/config.example.yaml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PROXYCTL_CRONTAB_FILE="$TMP/cron"
: >"$PROXYCTL_CRONTAB_FILE"
enable_timer
assert_contains "$(cat "$PROXYCTL_CRONTAB_FILE")" "BEGIN KEEP-CPA-OTD" "marker"
assert_contains "$(cat "$PROXYCTL_CRONTAB_FILE")" "proxyctl update all" "cmd"
disable_timer
if grep -q "BEGIN KEEP-CPA-OTD" "$PROXYCTL_CRONTAB_FILE"; then
  echo FAIL still present; ASSERT_FAILS=$((ASSERT_FAILS+1))
fi
finish_asserts
```

- [ ] **Step 2: Implement read/write helpers that use `crontab -l` unless `PROXYCTL_CRONTAB_FILE` set**

- [ ] **Step 3: Run tests — PASS; commit**

```bash
git add lib/timer.sh tests/test_timer.sh
git commit -m "feat: manage update crontab with KEEP-CPA-OTD markers"
```

---

### Task 8: Commands + `proxyctl` CLI

**Files:**
- Create: `lib/commands.sh`
- Create: `proxyctl`
- Create: `tests/test_cli_help.sh`
- Modify: `README.md` (full usage — can complete in Task 9 if preferred; include at least `--help` text here)

**Interfaces:**
- Produces executable `./proxyctl` with commands from spec
- `cmd_update name`: OLD_SHA → pull → compare → build+recreate → health → state file; rollback on failure
- `cmd_deploy`: ensure clone, generate compose, build, up; if target was all (caller tracks), enable_timer
- `cmd_undeploy [--purge]`

- [ ] **Step 1: Implement `proxyctl` dispatcher**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/registry.sh"
source "$ROOT_DIR/lib/compose.sh"
source "$ROOT_DIR/lib/git.sh"
source "$ROOT_DIR/lib/docker.sh"
source "$ROOT_DIR/lib/timer.sh"
source "$ROOT_DIR/lib/commands.sh"

usage() {
  cat <<'EOF'
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
EOF
}

main() {
  local cmd="${1:-help}"
  shift || true
  load_config
  case "$cmd" in
    deploy) cmd_deploy "$@" ;;
    undeploy) cmd_undeploy "$@" ;;
    start) cmd_start "$@" ;;
    stop) cmd_stop "$@" ;;
    restart) cmd_restart "$@" ;;
    status) cmd_status "$@" ;;
    update) require_cmds; cmd_update "$@" ;;
    logs) cmd_logs "$@" ;;
    enable-timer) cmd_enable_timer ;;
    disable-timer) cmd_disable_timer ;;
    help|-h|--help) usage ;;
    *) log_error "Unknown command: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
```

- [ ] **Step 2: Implement `cmd_update` with rollback (core logic)**

```bash
update_one() {
  local name="$1"
  local dest old new
  dest="$(service_dir "$name")"
  old="$(git -C "$dest" rev-parse HEAD)"
  if ! git_pull_ff "$name"; then
    log_update "[$name] pull failed"
    return 1
  fi
  new="$(git -C "$dest" rev-parse HEAD)"
  if [[ "$old" == "$new" ]]; then
    log_update "[$name] no update ($new)"
    return 0
  fi
  log_update "[$name] updated $old -> $new"
  if ! compose_build "$name" || ! compose_recreate "$name" || ! container_running "$name"; then
    log_update "[$name] deploy failed; rolling back to $old"
    git -C "$dest" reset --hard "$old"
    compose_build "$name" || true
    compose_recreate "$name" || true
    log_update "[$name] rollback attempted"
    return 1
  fi
  mkdir -p "$ROOT_DIR/runtime/state"
  echo "$new $(date -Iseconds)" >"$ROOT_DIR/runtime/state/$name"
  log_update "[$name] restarted ok"
  return 0
}

cmd_update() {
  local arg="${1:-all}" t rc=0
  generate_compose
  while IFS= read -r t; do
    update_one "$t" || rc=1
  done < <(resolve_targets "$arg")
  return "$rc"
}
```

Implement remaining commands analogously per spec:

- `cmd_deploy`: `require_cmds`; parse target; for each: `ensure_clone`; `generate_compose`; `compose_build`; `compose_up`; if original arg is `all` or empty: `enable_timer`. Also create host volume dirs; if CLIProxyAPI `config.yaml` missing after clone, copy `config.example.yaml` from the clone if present.
- `cmd_undeploy`: parse optional `--purge`; stop+rm; if all: `disable_timer`; purge deletes `service_dir` with `rm -rf` only when `--purge`.
- `cmd_status`: print table `NAME STATE SHA LAST_UPDATE` using `compose ps` and `runtime/state/$name`.
- `cmd_logs`: require name; pass through `-f`.

- [ ] **Step 3: Test help**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
out="$(bash "$ROOT/proxyctl" help)"
assert_contains "$out" "deploy" "help deploy"
assert_contains "$out" "update" "help update"
finish_asserts
```

Note: `proxyctl help` should not require docker/yq if possible — either lazy `require_cmds` only for docker-touching commands, or allow help before load_config fails. Prefer: `help` exits before `load_config` / `require_cmds`.

Adjust dispatcher so `help` does not call `load_config`.

- [ ] **Step 4: chmod +x proxyctl; run `bash tests/run.sh`**

- [ ] **Step 5: Commit**

```bash
git add proxyctl lib/commands.sh tests/test_cli_help.sh
git commit -m "feat: add proxyctl CLI for deploy, update, and lifecycle"
```

---

### Task 9: README + operator checklist

**Files:**
- Modify: `README.md`
- Create: `docs/superpowers/plans/manual-verification.md` OR section inside README

**Content must include:**

1. Prerequisites: Docker Compose v2, git, yq, bash
2. Server layout under `~/tools`
3. Clone toolkit; copy `config.example.yaml` → `config.yaml`
4. Prep notes: CLIProxyAPI needs config/auth dirs; commandcode-proxy may need env/auth depending on upstream README
5. Commands cheat sheet matching CLI table
6. Adding a new service (drop YAML + deploy)
7. Removing a service (`undeploy` then delete YAML)
8. Timer times (America/New_York 07:00 and 00:00)
9. Manual verification checklist:

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

- [ ] **Step 1: Write README**

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add server deploy and proxyctl usage guide"
```

---

### Task 10: Spec self-check polish

**Files:**
- Modify any gaps found vs spec (ports, purge flag parsing, `enabled: false` exclusion)

- [ ] **Step 1: Walk spec sections and verify each has code path**

Checklist:

| Spec item | Where |
|-----------|-------|
| deploy/undeploy/start/stop/restart/status/update/logs | `lib/commands.sh` |
| enable/disable timer | `lib/timer.sh` |
| registry YAML | `services/` |
| compose generation | `lib/compose.sh` |
| git pull + conditional rebuild | `cmd_update` |
| rollback | `update_one` |
| crontab TZ | `lib/timer.sh` |
| gitignore secrets/runtime | `.gitignore` |

- [ ] **Step 2: Run full `bash tests/run.sh`**

- [ ] **Step 3: Final commit if any fixes**

```bash
git add -A
git commit -m "fix: align proxyctl behavior with design spec"
```

(Only if there are changes.)

---

## Plan Self-Review

**Spec coverage:** Deploy, undeploy/--purge, lifecycle, status, update+rollback, logs, timer, registry scalability, TOOLS_DIR layout, crontab TZ, skip-on-same-SHA, continue-on-partial-failure — all mapped to tasks 1–10.

**Placeholders:** None intended; implementers should use the concrete code blocks as the starting point and only adjust for shell correctness (pipefail, mapfile).

**Type/name consistency:** `TOOLS_DIR`, `COMPOSE_PROJECT_NAME`, `generate_compose`, `resolve_targets`, `enable_timer`/`disable_timer`, `PROXYCTL_DOCKER_DRY_RUN`, `PROXYCTL_CRONTAB_FILE` used consistently across tasks.

**Dependency note:** `yq` (mikefarah) is required; README must document install.
