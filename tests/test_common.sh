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
assert_eq "keep-cpa-otd" "$COMPOSE_PROJECT_NAME" "project name"
assert_eq "$HOME/tools" "$TOOLS_DIR" "tools_dir expanded"
assert_contains "$UPDATE_CRON" "0 7 * * *" "cron morning"

finish_asserts
