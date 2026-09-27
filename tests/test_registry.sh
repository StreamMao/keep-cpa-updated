#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/registry.sh"
load_config "$ROOT/config.example.yaml"

names="$(list_services enabled | sort | tr '\n' ' ')"
assert_contains "$names" "cliproxyapi" "has cliproxyapi"
assert_contains "$names" "commandcode-proxy" "has commandcode-proxy"

dir="$(service_dir cliproxyapi)"
assert_eq "$TOOLS_DIR/CLIProxyAPI" "$dir" "service_dir"

targets="$(resolve_targets all | wc -l | tr -d ' ')"
assert_eq "2" "$targets" "all => 2"

if resolve_targets nosuch >/dev/null 2>&1; then
  echo "FAIL: unknown service should error" >&2
  ASSERT_FAILS=$((ASSERT_FAILS + 1))
fi

finish_asserts
