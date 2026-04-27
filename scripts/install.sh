#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <platform> [scope] <registry...>

Install one or more agents or skills from the registry.

Arguments:
  platform   opencode | claudecode | pi
  scope      local (default) | global
  registry   type:name pairs (e.g., skill:backend agent:researcher)

Registry patterns:
  skill:{name}
  agent:{name}
  command:{name}
  prompt:{name}

Examples:
  $(basename "$0") opencode skill:backend
  $(basename "$0") opencode local skill:backend agent:researcher
  $(basename "$0") claudecode global skill:frontend skill:backend agent:designer
EOF
  exit 1
}

[ $# -lt 2 ] && usage

PLATFORM="$1"
shift

validate_platform "$PLATFORM" || exit 1

if [[ "$1" == "local" || "$1" == "global" ]]; then
  SCOPE="$1"
  shift
else
  SCOPE="local"
fi

[ $# -eq 0 ] && usage

require_cmd yq
load_env
auto_pull_registry

FAILED=()
INSTALLED=()
TOTAL=$#

log_banner() {
  echo -e "\n${BOLD}${CYAN}╭──────────────────────────────────────${RESET}"
  echo -e "${BOLD}${CYAN}│ Agent Registry Manager — Install${RESET}"
  echo -e "${BOLD}${CYAN}│${RESET} ${DIM}platform: $PLATFORM · scope: $SCOPE · items: $TOTAL${RESET}"
  echo -e "${BOLD}${CYAN}╰──────────────────────────────────────${RESET}"
}

install_one() {
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

  if [ "$type" = "agent" ]; then
    require_cmd curl

    mkdir -p "$target_dir"
    local target_path="${target_dir%/}/${name}.md"

    echo -ne "  ${DIM}⠋${RESET} ${DIM}Downloading agent '$name'...${RESET}\r"
    if download_agent "$source_url" "$token" "$target_path"; then
      printf '                                                                   \r'
      log_ok "agent '$name' installed"
      log_info "→ $target_path"
      INSTALLED+=("$registry")
    else
      printf '                                                                   \r'
      log_fail "failed to download agent '$name'"
      log_info "ensure your GitHub App is installed on the repo and credentials are set in .env"
      rm -f "$target_path"
      FAILED+=("$registry")
    fi

    if [ "$resolved_platform" = "default" ] && [ "$PLATFORM" != "default" ]; then
      log_warn "No platform-specific agent for '$PLATFORM'. Installed base (default) version."
    fi
  else
    require_cmd git

    local skill_dir="${target_dir%/}/${name}/"
    echo -ne "  ${DIM}⠋${RESET} ${DIM}Downloading $type '$name'...${RESET}\r"
    if download_skill "$source_url" "$token" "$skill_dir"; then
      printf '                                                                   \r'
      log_ok "$type '$name' installed"
      log_info "→ $skill_dir"
      INSTALLED+=("$registry")
    else
      printf '                                                                   \r'
      log_fail "failed to download $type '$name'"
      log_info "ensure your GitHub App is installed on the repo and credentials are set in .env"
      rm -rf "$skill_dir"
      FAILED+=("$registry")
    fi
  fi
}

log_banner

idx=0
for item in "$@"; do
  idx=$((idx + 1))
  install_one "$item" "$idx"
done

echo -e "\n${BOLD}── Summary ──${RESET}"
if [ ${#INSTALLED[@]} -gt 0 ]; then
  echo -e "  ${GREEN}✔ Installed:${RESET} ${INSTALLED[*]}"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  echo -e "  ${RED}✘ Failed:${RESET}   ${FAILED[*]}" >&2
  echo ""
  exit 1
fi
echo ""
