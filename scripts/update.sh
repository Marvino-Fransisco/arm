#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <platform> [scope] <registry...>
       $(basename "$0") <platform> [scope] --all

Update one or more installed agents or skills to the latest version.
Backs up the current version and rolls back on failure.

Arguments:
  platform   opencode | claudecode | pi
  scope      project (default) | global
  registry   type:name pairs (e.g., skill:backend agent:researcher)

Options:
  --all, -a  Update all installed items (mutually exclusive with registry args)

Registry patterns:
  skill:{name}
  agent:{name}
  command:{name}
  prompt:{name}

Examples:
  $(basename "$0") opencode skill:backend
  $(basename "$0") opencode project skill:backend agent:researcher
  $(basename "$0") claudecode global skill:frontend agent:designer
  $(basename "$0") opencode --all
  $(basename "$0") claudecode global --all
EOF
  exit 1
}

ALL_MODE=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --all|-a) ALL_MODE=true ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

[ $# -lt 1 ] && usage

PLATFORM="$1"
shift

validate_platform "$PLATFORM" || exit 1

if [[ "${1:-}" == "project" || "${1:-}" == "global" ]]; then
  SCOPE="$1"
  shift
else
  SCOPE="project"
fi

if [ "$ALL_MODE" = true ]; then
  [ $# -gt 0 ] && { echo "Error: --all cannot be combined with explicit registry items" >&2; exit 1; }
else
  [ $# -eq 0 ] && usage
fi

require_cmd yq diff
load_env
auto_pull_registry

if [ "$ALL_MODE" = true ]; then
  mapfile -t REGISTRY_ITEMS < <(get_all_installed "$PLATFORM" "$SCOPE")
  if [ ${#REGISTRY_ITEMS[@]} -eq 0 ] || [ -z "${REGISTRY_ITEMS[0]:-}" ]; then
    log_banner
    echo -e "  ${DIM}● No installed items found for platform '$PLATFORM' (scope: $SCOPE)${RESET}"
    echo ""
    exit 0
  fi
  set -- "${REGISTRY_ITEMS[@]}"
fi

FAILED=()
UPDATED=()
SKIPPED=()
TOTAL=$#

log_banner() {
  echo -e "\n${BOLD}${CYAN}╭──────────────────────────────────────${RESET}"
  echo -e "${BOLD}${CYAN}│ Agent Registry Manager — Update${RESET}"
  echo -e "${BOLD}${CYAN}│${RESET} ${DIM}platform: $PLATFORM · scope: $SCOPE · items: $TOTAL${RESET}"
  echo -e "${BOLD}${CYAN}╰──────────────────────────────────────${RESET}"
}

update_one() {
  local registry="$1"
  local idx="$2"
  local type name

  log_step "[$idx/$TOTAL] Processing ${BOLD}$registry${RESET}"

  if ! parse_registry_pattern "$registry"; then
    log_fail "$PARSED_NAME"
    FAILED+=("$registry")
    return
  fi
  local type="$PARSED_TYPE"
  local name="$PARSED_NAME"

  local result
  result=$(find_in_registry "$type" "$name" "$PLATFORM") || true
  if [ -z "$result" ]; then
    log_fail "$type '$name' not found in registry.yaml"
    FAILED+=("$registry")
    return
  fi

  local contributor resolved_platform source_url
  contributor=$(echo "$result" | cut -d'|' -f1)
  resolved_platform=$(echo "$result" | cut -d'|' -f2)
  source_url=$(echo "$result" | cut -d'|' -f3-)

  log_info "contributor: $contributor"

  local token
  local parsed
  parsed=$(parse_github_url "$source_url")
  local owner=$(echo "$parsed" | cut -d'|' -f1)
  local repo=$(echo "$parsed" | cut -d'|' -f2)
  token=$(get_token "$contributor" "$owner/$repo")

  local target_dir
  target_dir=$(get_target_dir "$PLATFORM" "$type" "$SCOPE")
  if [ -z "$target_dir" ] || [ "$target_dir" = "null" ]; then
    log_fail "no $type directory configured for platform '$PLATFORM'"
    FAILED+=("$registry")
    return
  fi

  local BACKUP_DIR
  BACKUP_DIR=$(mktemp -d)

  if [ "$type" = "agent" ]; then
    require_cmd curl

    local target_path="${target_dir%/}/${name}.md"

    if [ ! -f "$target_path" ]; then
      log_fail "agent '$name' is not installed"
      log_info "run install first: scripts/install.sh $PLATFORM $SCOPE $registry"
      rm -rf "$BACKUP_DIR"
      FAILED+=("$registry")
      return
    fi

    echo -ne "  ${DIM}⠋${RESET} ${DIM}Backing up '$name'...${RESET}\r"
    cp "$target_path" "$BACKUP_DIR/${name}.md"

    echo -ne "  ${DIM}⠋${RESET} ${DIM}Downloading latest '$name'...${RESET}\r"
    if download_agent "$source_url" "$token" "$target_path" 2>/dev/null; then
      echo -e "                                                                   \r\c"
      if diff -q "$BACKUP_DIR/${name}.md" "$target_path" &>/dev/null; then
        log_ok "agent '$name' is already up to date"
        SKIPPED+=("$registry")
        rm -rf "$BACKUP_DIR"
      else
        log_ok "agent '$name' updated"
        log_info "changes:"
        diff -u "$BACKUP_DIR/${name}.md" "$target_path" | sed 's/^/    /' || true
        UPDATED+=("$registry")
        rm -rf "$BACKUP_DIR"
      fi
    else
      echo -e "                                                                   \r\c"
      log_fail "failed to download agent '$name'"
      log_info "restoring backup..."
      cp "$BACKUP_DIR/${name}.md" "$target_path"
      rm -rf "$BACKUP_DIR"
      log_info "rolled back to previous version"
      FAILED+=("$registry")
    fi

    if [ "$resolved_platform" = "default" ] && [ "$PLATFORM" != "default" ]; then
      log_warn "No platform-specific agent for '$PLATFORM'. Using base (default) version."
    fi
  else
    require_cmd git

    local target_path="${target_dir%/}/${name}/"

    if [ ! -d "$target_path" ]; then
      log_fail "$type '$name' is not installed"
      log_info "run install first: scripts/install.sh $PLATFORM $SCOPE $registry"
      rm -rf "$BACKUP_DIR"
      FAILED+=("$registry")
      return
    fi

    echo -ne "  ${DIM}⠋${RESET} ${DIM}Backing up '$name'...${RESET}\r"
    cp -r "$target_path" "$BACKUP_DIR/${name}/"

    echo -ne "  ${DIM}⠋${RESET} ${DIM}Downloading latest '$name'...${RESET}\r"
    if download_skill "$source_url" "$token" "$target_path" 2>/dev/null; then
      echo -e "                                                                   \r\c"
      if diff -rq "$BACKUP_DIR/${name}/" "$target_path" &>/dev/null; then
        log_ok "$type '$name' is already up to date"
        SKIPPED+=("$registry")
        rm -rf "$BACKUP_DIR"
      else
        log_ok "$type '$name' updated"
        log_info "changes:"
        diff -rq "$BACKUP_DIR/${name}/" "$target_path" | sed 's/^/    /' || true
        UPDATED+=("$registry")
        rm -rf "$BACKUP_DIR"
      fi
    else
      echo -e "                                                                   \r\c"
      log_fail "failed to download $type '$name'"
      log_info "restoring backup..."
      rm -rf "$target_path"
      cp -r "$BACKUP_DIR/${name}/" "$target_path"
      rm -rf "$BACKUP_DIR"
      log_info "rolled back to previous version"
      FAILED+=("$registry")
    fi
  fi
}

log_banner

idx=0
for item in "$@"; do
  idx=$((idx + 1))
  update_one "$item" "$idx"
done

echo -e "\n${BOLD}── Summary ──${RESET}"
if [ ${#UPDATED[@]} -gt 0 ]; then
  echo -e "  ${GREEN}✔ Updated:${RESET}  ${UPDATED[*]}"
fi
if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo -e "  ${DIM}● Skipped:${RESET}  ${SKIPPED[*]}"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  echo -e "  ${RED}✘ Failed:${RESET}   ${FAILED[*]}" >&2
  echo ""
  exit 1
fi
echo ""
