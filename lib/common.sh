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

# Expand ${TOOLS_DIR}, ${HOME}, and leading ~ on the host side of a volume spec.
expand_volume_spec() {
  local v="$1"
  v="${v//\$\{TOOLS_DIR\}/$TOOLS_DIR}"
  v="${v//\$\{HOME\}/$HOME}"
  if [[ "$v" == *:* ]]; then
    local host="${v%%:*}"
    local rest="${v#*:}"
    host="$(expand_path "$host")"
    echo "$host:$rest"
  else
    expand_path "$v"
  fi
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
  [[ "$missing" -eq 0 ]]
}

ensure_runtime_dirs() {
  mkdir -p "$ROOT_DIR/runtime/state"
}

_require_config_field() {
  local name="$1" value="$2"
  if [[ -z "$value" || "$value" == "null" ]]; then
    log_error "Invalid config: $name is missing or empty"
    return 1
  fi
}

load_config() {
  local cfg="${1:-$ROOT_DIR/config.yaml}"
  local raw
  if [[ ! -f "$cfg" ]]; then
    if [[ -f "$ROOT_DIR/config.example.yaml" ]]; then
      cp "$ROOT_DIR/config.example.yaml" "$cfg"
      log_info "Created $cfg from config.example.yaml"
    else
      log_error "No config at $cfg"
      return 1
    fi
  fi
  if ! raw="$(yq -r '.tools_dir' "$cfg")"; then
    log_error "Failed to read tools_dir from $cfg"
    return 1
  fi
  TOOLS_DIR="$(expand_path "$raw")"
  _require_config_field tools_dir "$TOOLS_DIR" || return 1

  if ! raw="$(yq -r '.timezone' "$cfg")"; then
    log_error "Failed to read timezone from $cfg"
    return 1
  fi
  TIMEZONE="$raw"
  _require_config_field timezone "$TIMEZONE" || return 1

  if ! raw="$(yq -r '.compose_project_name' "$cfg")"; then
    log_error "Failed to read compose_project_name from $cfg"
    return 1
  fi
  COMPOSE_PROJECT_NAME="$raw"
  _require_config_field compose_project_name "$COMPOSE_PROJECT_NAME" || return 1

  if ! UPDATE_CRON="$(yq -r '.update_cron[]' "$cfg")"; then
    log_error "Failed to read update_cron from $cfg"
    return 1
  fi
  if [[ -z "$UPDATE_CRON" ]]; then
    log_error "Invalid config: update_cron is missing or empty"
    return 1
  fi
  export TOOLS_DIR TIMEZONE COMPOSE_PROJECT_NAME UPDATE_CRON
}
