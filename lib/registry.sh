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

service_exists() {
  service_file_for "$1" >/dev/null
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
