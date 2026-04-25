#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Scan contributor repos for agents/, skills/, commands/, prompts/ directories
and sync entries into the local registry.yaml. Adds new items, removes
items that no longer exist in the repo.

Requires: yq, curl
EOF
  exit 1
}

require_cmd yq curl
load_env

parse_repo_url() {
  echo "$1" | sed 's|https://github.com/||' | sed 's|.git$||'
}

detect_branch() {
  local owner_repo="$1"
  local token="$2"
  local auth=()
  [ -n "$token" ] && auth=(-H "Authorization: token $token")

  for branch in main master; do
    if curl -fsSL -o /dev/null ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$owner_repo/branches/$branch" 2>/dev/null; then
      echo "$branch"
      return
    fi
  done
  echo "main"
}

fetch_dir_listing() {
  local owner_repo="$1"
  local path="$2"
  local token="$3"
  local auth=()
  [ -n "$token" ] && auth=(-H "Authorization: token $token")

  curl -fsSL ${auth[@]+"${auth[@]}"} "https://api.github.com/repos/$owner_repo/contents/$path" 2>/dev/null || echo "[]"
}

add_entry() {
  local section="$1"
  local contributor="$2"
  local name="$3"
  local source_url="$4"
  local platform="$5"

  local yq_path=".$section.\"$contributor\""
  [ -n "$platform" ] && yq_path="${yq_path}.${platform}"
  yq_path="${yq_path}.\"$name\""

  local existing
  existing=$(yq -r "${yq_path}.source" "$REGISTRY" 2>/dev/null || true)
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    return 1
  fi

  yq -i "${yq_path}.source = \"$source_url\"" "$REGISTRY"
  yq -i "${yq_path}.description = \"\"" "$REGISTRY"
  local type_name="${section#registry.}"
  echo "$type_name/$name ($contributor)" >> "$ADDED_LOG"
}

remove_entry() {
  local section="$1"
  local contributor="$2"
  local name="$3"
  local platform="$4"

  local yq_path=".$section.\"$contributor\""
  [ -n "$platform" ] && yq_path="${yq_path}.${platform}"
  yq_path="${yq_path}.\"$name\""

  yq -i "del(${yq_path})" "$REGISTRY"
  local type_name="${section#registry.}"
  echo "$type_name/$name ($contributor)" >> "$REMOVED_LOG"
}

sync_dir() {
  local dir_type="$1"
  local owner_repo="$2"
  local branch="$3"
  local contributor="$4"
  local token="$5"

  local section="registry.$dir_type"
  local listing
  listing=$(fetch_dir_listing "$owner_repo" "$dir_type" "$token")

  if [ "$listing" = "[]" ]; then
    return
  fi

  local added=0
  local removed=0

  if [ "$dir_type" = "agents" ]; then
    local platforms
    platforms=$(echo "$listing" | yq -r '.[] | select(.type == "dir") | .name' 2>/dev/null)

    for platform in $platforms; do
      [ -z "$platform" ] && continue

      local platform_listing
      platform_listing=$(fetch_dir_listing "$owner_repo" "$dir_type/$platform" "$token")
      [ "$platform_listing" = "[]" ] && continue

      local remote_names
      remote_names=$(echo "$platform_listing" | yq -r '.[] | select(.type == "file" and (.name | test("\\.md$"))) | .name' 2>/dev/null | sed 's/\.md$//')

      for name in $remote_names; do
        [ -z "$name" ] && continue
        local source_url="https://github.com/$owner_repo/blob/$branch/$dir_type/$platform/$name.md"
        if add_entry "$section" "$contributor" "$name" "$source_url" "$platform"; then
          added=$((added + 1))
        fi
      done

      local local_names
      local_names=$(yq ".$section.\"$contributor\".\"$platform\" | keys | .[]" "$REGISTRY" 2>/dev/null || true)

      for name in $local_names; do
        [ -z "$name" ] || [ "$name" = "null" ] && continue
        local found=false
        for remote in $remote_names; do
          [ "$name" = "$remote" ] && found=true && break
        done
        if [ "$found" = "false" ]; then
          remove_entry "$section" "$contributor" "$name" "$platform"
          removed=$((removed + 1))
        fi
      done
    done
  else
    local remote_names
    remote_names=$(echo "$listing" | yq -r '.[] | select(.type == "dir") | .name' 2>/dev/null)

    for name in $remote_names; do
      [ -z "$name" ] && continue
      local source_url="https://github.com/$owner_repo/tree/$branch/$dir_type/$name"
      if add_entry "$section" "$contributor" "$name" "$source_url" ""; then
        added=$((added + 1))
      fi
    done

    local local_names
    local_names=$(yq ".$section.\"$contributor\" | keys | .[]" "$REGISTRY" 2>/dev/null || true)

    for name in $local_names; do
      [ -z "$name" ] || [ "$name" = "null" ] && continue
      local found=false
      for remote in $remote_names; do
        [ "$name" = "$remote" ] && found=true && break
      done
      if [ "$found" = "false" ]; then
        remove_entry "$section" "$contributor" "$name" ""
        removed=$((removed + 1))
      fi
    done
  fi

  if [ "$added" -eq 0 ] && [ "$removed" -eq 0 ]; then
    echo "  $dir_type: up to date"
  else
    echo "  $dir_type: $added added, $removed removed"
  fi
}

ADDED_LOG=$(mktemp)
REMOVED_LOG=$(mktemp)
trap 'rm -f "$ADDED_LOG" "$REMOVED_LOG"' EXIT

echo "Syncing registry from contributor repos..."
echo ""

PRE_SYNC_HASH=$(shasum "$REGISTRY" | cut -d' ' -f1)

for contributor in $(yq '.contributors | keys | .[]' "$CONTRIBUTORS" 2>/dev/null); do
  [ -z "$contributor" ] && continue

  repo_count=$(yq ".contributors.\"$contributor\".gh-repo | length" "$CONTRIBUTORS" 2>/dev/null)
  if [ "$repo_count" = "0" ] || [ "$repo_count" = "null" ]; then
    echo "[$contributor] No repos configured. Skipping."
    continue
  fi

  echo "[$contributor] Syncing..."

  for i in $(seq 0 $((repo_count - 1))); do
    repo_url=$(yq -r ".contributors.\"$contributor\".gh-repo[$i]" "$CONTRIBUTORS" 2>/dev/null)
    owner_repo=$(parse_repo_url "$repo_url")
    token=$(get_token "$contributor" "$owner_repo")
    branch=$(detect_branch "$owner_repo" "$token")

    echo "  Repo: $owner_repo ($branch)"

    for dir_type in agents skills commands prompts; do
      sync_dir "$dir_type" "$owner_repo" "$branch" "$contributor" "$token"
    done
  done
done

POST_SYNC_HASH=$(shasum "$REGISTRY" | cut -d' ' -f1)

echo ""

total_added=$(wc -l < "$ADDED_LOG" | tr -d ' ')
total_removed=$(wc -l < "$REMOVED_LOG" | tr -d ' ')

if [ "$total_added" -gt 0 ]; then
  echo -e "${GREEN}${BOLD}Added ($total_added):${RESET}"
  while IFS= read -r line; do
    log_ok "$line"
  done < "$ADDED_LOG"
  echo ""
fi

if [ "$total_removed" -gt 0 ]; then
  echo -e "${RED}${BOLD}Removed ($total_removed):${RESET}"
  while IFS= read -r line; do
    log_fail "$line"
  done < "$REMOVED_LOG"
  echo ""
fi

if [ "$PRE_SYNC_HASH" = "$POST_SYNC_HASH" ]; then
  log_info "No changes detected. Registry is up to date."
else
  log_step "Registry changed. Running parse-registry..."
  "$SCRIPT_DIR/parse-registry.sh"
fi
