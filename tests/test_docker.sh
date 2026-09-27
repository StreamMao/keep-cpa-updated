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
assert_contains "$out" "keep-cpa-otd" "project"
finish_asserts
