#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/helpers.sh"

stub_bin="$(mktemp -d)"
cat >"$stub_bin/docker" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "compose" && "$2" == "version" ]]; then
  exit 0
fi
exit 0
EOF
chmod +x "$stub_bin/docker"

export PATH="$stub_bin:${HOME}/.local/bin:${PATH}"
set +e
out="$(bash "$ROOT/proxyctl" status nosuch 2>&1)"
rc=$?
set -e

assert_contains "$out" "Unknown service" "unknown service message"
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: proxyctl status nosuch should exit non-zero (got $rc)" >&2
  ASSERT_FAILS=$((ASSERT_FAILS + 1))
fi

finish_asserts
