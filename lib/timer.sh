#!/usr/bin/env bash
# shellcheck shell=bash

_TIMER_BEGIN='# BEGIN KEEP-CPA-OTD'
_TIMER_END='# END KEEP-CPA-OTD'

_crontab_read() {
  if [[ -n "${PROXYCTL_CRONTAB_FILE:-}" ]]; then
    if [[ -f "$PROXYCTL_CRONTAB_FILE" ]]; then
      cat "$PROXYCTL_CRONTAB_FILE"
    fi
    return 0
  fi
  crontab -l 2>/dev/null || true
}

_crontab_write() {
  local content="$1"
  if [[ -n "${PROXYCTL_CRONTAB_FILE:-}" ]]; then
    printf '%s\n' "$content" >"$PROXYCTL_CRONTAB_FILE"
  else
    printf '%s\n' "$content" | crontab -
  fi
}

_strip_timer_block() {
  awk -v begin="$_TIMER_BEGIN" -v end="$_TIMER_END" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip { print }
  ' <<< "$1"
}

_build_timer_block() {
  local proxyctl="$ROOT_DIR/proxyctl"
  local log="$ROOT_DIR/runtime/cron.log"
  local schedule
  echo "$_TIMER_BEGIN"
  echo "TZ=$TIMEZONE"
  while IFS= read -r schedule; do
    [[ -z "$schedule" ]] && continue
    echo "$schedule $proxyctl update all >>$log 2>&1"
  done <<< "$UPDATE_CRON"
  echo "$_TIMER_END"
}

enable_timer() {
  local existing stripped block new_content
  existing="$(_crontab_read)"
  stripped="$(_strip_timer_block "$existing")"
  block="$(_build_timer_block)"
  stripped="$(printf '%s' "$stripped" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
  if [[ -n "$stripped" ]]; then
    new_content="${stripped}"$'\n'"${block}"
  else
    new_content="${block}"
  fi
  _crontab_write "$new_content"
}

disable_timer() {
  local existing stripped
  existing="$(_crontab_read)"
  stripped="$(_strip_timer_block "$existing")"
  stripped="$(printf '%s' "$stripped" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
  _crontab_write "$stripped"
}

timer_installed() {
  local content
  content="$(_crontab_read)"
  grep -q "^${_TIMER_BEGIN}\$" <<< "$content" 2>/dev/null
}
