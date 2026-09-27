#!/usr/bin/env bash
# shellcheck shell=bash

_prepare_service_host_dirs() {
  local name="$1" f vol host
  f="$(service_file_for "$name")" || return 1
  local -a vols
  mapfile -t vols < <(yq -r '.volumes[]?' "$f" 2>/dev/null || true)
  for vol in "${vols[@]}"; do
    [[ -z "$vol" || "$vol" == "null" ]] && continue
    vol="${vol//\$\{TOOLS_DIR\}/$TOOLS_DIR}"
    host="${vol%%:*}"
    [[ "$host" == "$vol" ]] && continue
    if [[ "$host" == *.yaml || "$host" == *.yml ]]; then
      mkdir -p "$(dirname "$host")"
    else
      mkdir -p "$host"
    fi
  done
  if [[ "$name" == "cliproxyapi" ]]; then
    local cfg="$TOOLS_DIR/CLIProxyAPI/config.yaml"
    if [[ ! -f "$cfg" ]]; then
      local ex
      ex="$(service_dir "$name")/config.example.yaml"
      if [[ -f "$ex" ]]; then
        cp "$ex" "$cfg"
        log_info "Created $cfg from repo config.example.yaml"
      fi
    fi
  fi
}

update_one() {
  local name="$1"
  local dest old new
  dest="$(service_dir "$name")"
  if [[ ! -d "$dest/.git" ]]; then
    log_update "[$name] no clone at $dest"
    return 1
  fi
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

cmd_deploy() {
  require_cmds || return 1
  local arg="all"
  if [[ $# -gt 0 ]]; then
    if [[ "$1" == "--" ]]; then
      shift
    fi
    arg="${1:-all}"
  fi
  mkdir -p "$TOOLS_DIR"
  local t
  while IFS= read -r t; do
    ensure_clone "$t"
    _prepare_service_host_dirs "$t"
  done < <(resolve_targets "$arg")
  generate_compose
  while IFS= read -r t; do
    compose_build "$t"
    compose_up "$t"
  done < <(resolve_targets "$arg")
  if [[ "$arg" == "all" ]]; then
    enable_timer
  fi
}

cmd_undeploy() {
  require_cmds || return 1
  local purge=0 arg="all"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --purge) purge=1; shift ;;
      --)
        shift
        [[ $# -gt 0 ]] && arg="$1"
        break
        ;;
      *) arg="$1"; shift ;;
    esac
  done
  generate_compose
  local t
  while IFS= read -r t; do
    compose_stop "$t" || true
    compose_rm "$t" || true
    if [[ "$purge" -eq 1 ]]; then
      rm -rf "$(service_dir "$t")"
      log_info "Purged clone for $t"
    fi
  done < <(resolve_targets "$arg")
  if [[ "$arg" == "all" ]]; then
    disable_timer
  fi
}

cmd_start() {
  require_cmds || return 1
  local arg="${1:-all}" t
  generate_compose
  while IFS= read -r t; do
    compose_up "$t"
  done < <(resolve_targets "$arg")
}

cmd_stop() {
  require_cmds || return 1
  local arg="${1:-all}" t
  generate_compose
  while IFS= read -r t; do
    compose_stop "$t"
  done < <(resolve_targets "$arg")
}

cmd_restart() {
  require_cmds || return 1
  local arg="${1:-all}" t
  generate_compose
  while IFS= read -r t; do
    compose_restart "$t"
  done < <(resolve_targets "$arg")
}

cmd_status() {
  require_cmds || return 1
  local arg="${1:-all}" t state sha last sha_file
  generate_compose
  printf "%-22s %-10s %-8s %s\n" "NAME" "STATE" "SHA" "LAST_UPDATE"
  while IFS= read -r t; do
    state="stopped"
    if container_running "$t"; then
      state="running"
    fi
    sha="-"
    if [[ -d "$(service_dir "$t")/.git" ]]; then
      sha="$(git_sha_short "$t" 2>/dev/null || echo "-")"
    fi
    last="-"
    sha_file="$ROOT_DIR/runtime/state/$t"
    if [[ -f "$sha_file" ]]; then
      read -r _ last <"$sha_file" || true
    fi
    printf "%-22s %-10s %-8s %s\n" "$t" "$state" "$sha" "$last"
  done < <(resolve_targets "$arg")
}

cmd_logs() {
  require_cmds || return 1
  if [[ $# -lt 1 ]]; then
    log_error "logs requires a service name"
    return 1
  fi
  local name="$1"
  shift || true
  if ! service_exists "$name"; then
    log_error "Unknown service: $name"
    log_error "Known: $(list_services all | tr '\n' ' ')"
    return 1
  fi
  generate_compose
  compose_logs "$name" "$@"
}

cmd_enable_timer() {
  enable_timer
  log_info "Update timer enabled"
}

cmd_disable_timer() {
  disable_timer
  log_info "Update timer disabled"
}
