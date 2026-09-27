#!/usr/bin/env bash

generate_compose() {
  ensure_runtime_dirs
  local out="$ROOT_DIR/runtime/docker-compose.yml"
  local tmp
  tmp="$(mktemp)"
  {
    echo "services:"
    local name f ctx bctx df restart volcount ef
    local -a ports volumes
    for name in $(list_services enabled); do
      f="$(service_file_for "$name")"
      bctx="$(yq -r '.build.context' "$f")"
      if [[ "$bctx" == "." ]]; then
        ctx="$(service_dir "$name")"
      else
        ctx="$(service_dir "$name")/$bctx"
      fi
      df="$(yq -r '.build.dockerfile' "$f")"
      restart="$(yq -r '.restart' "$f")"
      echo "  $name:"
      echo "    build:"
      echo "      context: $ctx"
      echo "      dockerfile: $df"
      echo "    restart: $restart"
      echo "    ports:"
      mapfile -t ports < <(yq -r '.ports[]' "$f")
      local p
      for p in "${ports[@]}"; do
        echo "      - \"$p\""
      done
      volcount="$(yq -r '.volumes | length' "$f")"
      if [[ "$volcount" != "0" && "$volcount" != "null" ]]; then
        echo "    volumes:"
        mapfile -t volumes < <(yq -r '.volumes[]' "$f")
        local v
        for v in "${volumes[@]}"; do
          v="${v//\$\{TOOLS_DIR\}/$TOOLS_DIR}"
          echo "      - \"$v\""
        done
      fi
      if [[ "$(yq -r '.environment | type' "$f")" == "!!map" ]]; then
        echo "    environment:"
        yq -r '.environment | to_entries[] | "      \(.key): \"\(.value)\""' "$f"
      fi
      ef="$(yq -r '.env_file' "$f")"
      if [[ "$ef" != "null" && -n "$ef" ]]; then
        echo "    env_file:"
        echo "      - $(expand_path "$ef")"
      fi
    done
  } >"$tmp"
  mv "$tmp" "$out"
}
