#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"
source "$ROOT/lib/common.sh"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/git.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
TOOLS_DIR="$TMP/tools"
mkdir -p "$TOOLS_DIR"

git init -b main "$TMP/upstream"
git -C "$TMP/upstream" config user.email t@t
git -C "$TMP/upstream" config user.name t
echo hi >"$TMP/upstream/README"
git -C "$TMP/upstream" add README
git -C "$TMP/upstream" commit -m init

ensure_repo "$TMP/upstream" "main" "$TOOLS_DIR/fake"
assert_file_exists "$TOOLS_DIR/fake/README"
sha1="$(git -C "$TOOLS_DIR/fake" rev-parse HEAD)"
echo bye >>"$TMP/upstream/README"
git -C "$TMP/upstream" commit -am next
git_pull_ff_repo "$TOOLS_DIR/fake"
sha2="$(git -C "$TOOLS_DIR/fake" rev-parse HEAD)"
[[ "$sha1" != "$sha2" ]] || { echo FAIL no pull; exit 1; }

finish_asserts
