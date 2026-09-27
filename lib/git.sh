#!/usr/bin/env bash

ensure_repo() {
  local repo="$1" branch="$2" dest="$3"
  if [[ ! -d "$dest/.git" ]]; then
    mkdir -p "$(dirname "$dest")"
    git clone --branch "$branch" "$repo" "$dest"
  else
    git -C "$dest" fetch --prune origin
    git -C "$dest" checkout "$branch"
  fi
}

ensure_clone() {
  local name="$1"
  ensure_repo "$(service_field "$name" repo)" "$(service_field "$name" branch)" "$(service_dir "$name")"
}

git_sha() { git -C "$(service_dir "$1")" rev-parse HEAD; }
git_sha_short() { git -C "$(service_dir "$1")" rev-parse --short HEAD; }

git_pull_ff_repo() {
  local dest="$1"
  git -C "$dest" fetch --prune origin
  git -C "$dest" pull --ff-only
}

git_pull_ff() {
  git_pull_ff_repo "$(service_dir "$1")"
}
