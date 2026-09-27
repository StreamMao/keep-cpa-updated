#!/usr/bin/env bash
# shellcheck shell=bash

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
compose_recreate() { _run_compose up -d --force-recreate --build "$@"; }
compose_stop() { _run_compose stop "$@"; }
compose_rm() { _run_compose rm -f "$@"; }
compose_restart() { _run_compose restart "$@"; }
compose_ps() { _run_compose ps "$@"; }
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

container_id() {
  local name="$1" id
  if [[ "${PROXYCTL_DOCKER_DRY_RUN:-0}" == "1" ]]; then
    echo "-"
    return 0
  fi
  id="$(_run_compose ps -q "$name" 2>/dev/null | head -n1 || true)"
  if [[ -n "$id" ]]; then
    echo "${id:0:12}"
  else
    echo "-"
  fi
}
