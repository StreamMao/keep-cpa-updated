#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
out="$(bash "$ROOT/proxyctl" help)"
assert_contains "$out" "deploy" "help deploy"
assert_contains "$out" "update" "help update"
finish_asserts
