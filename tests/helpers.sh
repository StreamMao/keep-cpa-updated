#!/usr/bin/env bash
set -euo pipefail

ASSERT_FAILS=0

assert_eq() {
  local want="$1" got="$2" msg="${3:-}"
  if [[ "$want" != "$got" ]]; then
    echo "FAIL assert_eq ${msg}: want=[$want] got=[$got]" >&2
    ASSERT_FAILS=$((ASSERT_FAILS + 1))
  fi
}

assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "FAIL assert_file_exists: $path" >&2
    ASSERT_FAILS=$((ASSERT_FAILS + 1))
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "FAIL assert_contains ${msg}: missing [$needle]" >&2
    ASSERT_FAILS=$((ASSERT_FAILS + 1))
  fi
}

finish_asserts() {
  if [[ "$ASSERT_FAILS" -ne 0 ]]; then
    echo "FAILED with $ASSERT_FAILS assertion(s)" >&2
    exit 1
  fi
  echo "OK"
}
