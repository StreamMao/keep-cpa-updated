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

BAD_CFG="$TMP/bad-config.yaml"
yq 'del(.compose_project_name)' "$CFG" >"$BAD_CFG"
set +e
load_config "$BAD_CFG" >/dev/null 2>&1
bad_rc=$?
set -e
assert_eq 1 "$bad_rc" "load_config rejects missing compose_project_name"

finish_asserts
