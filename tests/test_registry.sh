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

disabled_fixture="$ROOT/services/disabled-fixture.yaml"
trap 'rm -f "$disabled_fixture"' EXIT
cat >"$disabled_fixture" <<'EOF'
name: disabled-fixture
repo: https://example.com/disabled.git
branch: main
dir: disabled-fixture
build:
  context: .
  dockerfile: Dockerfile
ports: []
enabled: false
EOF
enabled_names="$(list_services enabled | tr '\n' ' ')"
if [[ "$enabled_names" == *"disabled-fixture"* ]]; then
  echo "FAIL: enabled:false service must not appear in list_services enabled" >&2
  ASSERT_FAILS=$((ASSERT_FAILS + 1))
fi
assert_contains "$(list_services all | tr '\n' ' ')" "disabled-fixture" "disabled still in all registry"
targets="$(resolve_targets all | wc -l | tr -d ' ')"
assert_eq "2" "$targets" "all still only enabled services"

# Caller varname "targets" must not be shadowed by read_resolve_targets locals (set -u).
_check_read_resolve() {
  local targets
  read_resolve_targets all targets || return 1
  assert_contains "$targets" "cliproxyapi" "read_resolve_targets sets caller targets"
  assert_contains "$targets" "commandcode-proxy" "read_resolve_targets includes both"
}
if ! _check_read_resolve; then
  echo "FAIL: read_resolve_targets all" >&2
  ASSERT_FAILS=$((ASSERT_FAILS + 1))
fi

finish_asserts
