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
assert_contains "$body" "$HOME/.cli-proxy-api:/root/.cli-proxy-api" "official auth-dir mount"

finish_asserts
