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
