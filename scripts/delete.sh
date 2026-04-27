#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <platform> [scope] <registry...>
       $(basename "$0") <platform> [scope] --all

Delete one or more installed agents or skills. Items must exist in registry.yaml.

Arguments:
  platform   opencode | claudecode | pi
  scope      local (default) | global
  registry   type:name pairs (e.g., skill:backend agent:researcher)

Options:
  --all, -a  Delete all installed items (mutually exclusive with registry args)

Registry patterns:
  skill:{name}
  agent:{name}
  command:{name}
  prompt:{name}

Examples:
  $(basename "$0") opencode skill:backend
  $(basename "$0") opencode local skill:backend agent:researcher
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

if [[ "${1:-}" == "local" || "${1:-}" == "global" ]]; then
  SCOPE="$1"
  shift
else
  SCOPE="local"
fi

if [ "$ALL_MODE" = true ]; then
  [ $# -gt 0 ] && { echo "Error: --all cannot be combined with explicit registry items" >&2; exit 1; }
else
  [ $# -eq 0 ] && usage
fi

require_cmd yq

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
DELETED=()
TOTAL=$#

log_banner() {
  echo -e "\n${BOLD}${CYAN}╭──────────────────────────────────────${RESET}"
  echo -e "${BOLD}${CYAN}│ Agent Registry Manager — Delete${RESET}"
  echo -e "${BOLD}${CYAN}│${RESET} ${DIM}platform: $PLATFORM · scope: $SCOPE · items: $TOTAL${RESET}"
  echo -e "${BOLD}${CYAN}╰──────────────────────────────────────${RESET}"
}

delete_one() {
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

  if ! find_in_registry "$type" "$name" "$PLATFORM" >/dev/null 2>&1; then
    log_fail "$type '$name' is not in registry.yaml — only registry items can be deleted"
    FAILED+=("$registry")
    return
  fi

  local target_dir
  target_dir=$(get_target_dir "$PLATFORM" "$type" "$SCOPE")
  if [ -z "$target_dir" ] || [ "$target_dir" = "null" ]; then
    log_fail "no $type directory configured for platform '$PLATFORM'"
    FAILED+=("$registry")
    return
  fi

  if [ "$type" = "agent" ]; then
    local target_path="${target_dir%/}/${name}.md"
    if [ -f "$target_path" ]; then
      rm "$target_path"
      log_ok "agent '$name' deleted"
      log_info "→ $target_path"
      DELETED+=("$registry")
    else
      log_fail "agent '$name' is not installed at $target_path"
      FAILED+=("$registry")
    fi
  else
    local target_path="${target_dir%/}/${name}/"
    if [ -d "$target_path" ]; then
      rm -rf "$target_path"
      log_ok "$type '$name' deleted"
      log_info "→ $target_path"
      DELETED+=("$registry")
    else
      log_fail "$type '$name' is not installed at $target_path"
      FAILED+=("$registry")
    fi
  fi

  log_info "entry '$name' remains in registry.yaml for future re-installation"
}

log_banner

idx=0
for item in "$@"; do
  idx=$((idx + 1))
  delete_one "$item" "$idx"
done

echo -e "\n${BOLD}── Summary ──${RESET}"
if [ ${#DELETED[@]} -gt 0 ]; then
  echo -e "  ${GREEN}✔ Deleted:${RESET}  ${DELETED[*]}"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  echo -e "  ${RED}✘ Failed:${RESET}   ${FAILED[*]}" >&2
  echo ""
  exit 1
fi
echo ""
