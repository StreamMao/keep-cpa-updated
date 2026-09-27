#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=helpers.sh
source "$ROOT/tests/helpers.sh"
assert_file_exists "$ROOT/config.example.yaml"
assert_file_exists "$ROOT/.gitignore"
finish_asserts
