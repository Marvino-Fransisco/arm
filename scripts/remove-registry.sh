#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

AGENT_REGISTRY="$HOME/agent-registry"

CONTRIBUTOR=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --contributor <name> <registry...>

Remove items from the registry.yaml and delete the corresponding
files from ~/agent-registry/.

Options:
  --contributor <name>   Contributor key in registry.yaml (required)

Arguments:
  registry   type:name pairs (e.g., skill:backend agent:researcher)

Registry patterns:
  agent:{name}
  skill:{name}
  command:{name}
  prompt:{name}

Examples:
  $(basename "$0") --contributor mf skill:backend
  $(basename "$0") --contributor mf agent:researcher skill:frontend
EOF
  exit 1
}

ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --contributor)
      CONTRIBUTOR="${2:-}"
      [ -z "$CONTRIBUTOR" ] && { echo "Error: --contributor requires a value" >&2; usage; }
      shift 2
      ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

[ -z "$CONTRIBUTOR" ] && { echo "Error: --contributor is required" >&2; usage; }
[ $# -lt 1 ] && usage

require_cmd yq

sanitize_yq_key "$CONTRIBUTOR" || { echo "Error: invalid contributor key '$CONTRIBUTOR'" >&2; exit 1; }

REMOVED=()
FAILED=()
TOTAL=$#

log_banner() {
  echo -e "\n${BOLD}${CYAN}╭──────────────────────────────────────${RESET}"
  echo -e "${BOLD}${CYAN}│ Agent Registry Manager — Remove Registry${RESET}"
  echo -e "${BOLD}${CYAN}│${RESET} ${DIM}contributor: $CONTRIBUTOR · items: $TOTAL${RESET}"
  echo -e "${BOLD}${CYAN}╰──────────────────────────────────────${RESET}"
}

remove_registry_file() {
  local type="$1"
  local name="$2"
  local source_url="$3"

  local parsed
  parsed=$(parse_github_url "$source_url")
  local path=$(echo "$parsed" | cut -d'|' -f4)

  if [ "$type" = "agent" ]; then
    local file_path="$AGENT_REGISTRY/$path"
    if [ -f "$file_path" ]; then
      rm "$file_path"
      log_info "deleted file: $file_path"
    else
      log_warn "file not found (already removed?): $file_path"
    fi
  else
    local dir_path="$AGENT_REGISTRY/$path"
    if [ -d "$dir_path" ]; then
      rm -rf "$dir_path"
      log_info "deleted directory: $dir_path"
    else
      log_warn "directory not found (already removed?): $dir_path"
    fi
  fi
}

remove_one() {
  local registry="$1"
  local idx="$2"

  log_step "[$idx/$TOTAL] Processing ${BOLD}$registry${RESET}"

  if ! parse_registry_pattern "$registry"; then
    log_fail "$PARSED_NAME"
    FAILED+=("$registry")
    return
  fi
  local type="$PARSED_TYPE"
  local name="$PARSED_NAME"

  local registry_key
  case "$type" in
    agent)  registry_key="agents" ;;
    skill)  registry_key="skills" ;;
    command) registry_key="commands" ;;
    prompt) registry_key="prompts" ;;
  esac

  log_info "contributor: $CONTRIBUTOR"

  if [ "$type" = "agent" ]; then
    local platforms
    platforms=$(yq ".registry.${registry_key}.\"$CONTRIBUTOR\" | keys | .[]" "$REGISTRY" 2>/dev/null || true)
    local found=false
    for platform in $platforms; do
      [ -z "$platform" ] && continue
      local src
      src=$(yq -r ".registry.${registry_key}.\"$CONTRIBUTOR\".\"$platform\".\"$name\".source" "$REGISTRY" 2>/dev/null)
      if [ -n "$src" ] && [ "$src" != "null" ]; then
        yq -i "del(.registry.${registry_key}.\"$CONTRIBUTOR\".\"$platform\".\"$name\")" "$REGISTRY"
        remove_registry_file "$type" "$name" "$src"
        found=true
      fi
    done
    if [ "$found" = false ]; then
      log_fail "agent '$name' not found under any platform for contributor '$CONTRIBUTOR'"
      FAILED+=("$registry")
      return
    fi
  else
    local src
    src=$(yq -r ".registry.${registry_key}.\"$CONTRIBUTOR\".\"$name\".source" "$REGISTRY" 2>/dev/null)
    if [ -z "$src" ] || [ "$src" = "null" ]; then
      log_fail "$type '$name' not found for contributor '$CONTRIBUTOR' in registry.yaml"
      FAILED+=("$registry")
      return
    fi
    yq -i "del(.registry.${registry_key}.\"$CONTRIBUTOR\".\"$name\")" "$REGISTRY"
    remove_registry_file "$type" "$name" "$src"
  fi

  log_ok "$type '$name' removed from registry and agent-registry"
  REMOVED+=("$registry")
}

log_banner

idx=0
for item in "$@"; do
  idx=$((idx + 1))
  remove_one "$item" "$idx"
done

log_step "Regenerating registry.md"
"$SCRIPT_DIR/parse-registry.sh"

echo -e "\n${BOLD}── Summary ──${RESET}"
if [ ${#REMOVED[@]} -gt 0 ]; then
  echo -e "  ${GREEN}✔ Removed:${RESET}  ${REMOVED[*]}"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  echo -e "  ${RED}✘ Failed:${RESET}   ${FAILED[*]}" >&2
  echo ""
  exit 1
fi
echo ""
