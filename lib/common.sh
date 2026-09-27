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
  [[ "$missing" -eq 0 ]]
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
