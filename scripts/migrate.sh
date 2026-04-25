#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

DEST_ROOT="$HOME/agent-registry"

require_cmd yq

usage() {
  cat <<EOF
Usage: $(basename "$0") --contributor <name> <scope> <platform> [items...]

Migrate agents, skills, commands, and prompts from a platform config
directory into the local agent-registry repository at ~/agent-registry/.

Only the specific files/folders being migrated are replaced in the
destination. Other items are left untouched.

New items are automatically added to registry.yaml under the given
contributor.

Options:
  --contributor <name>  Contributor key from contributors.yaml (required)

Arguments:
  scope     global | local
            global  — source root is ~/ (home directory)
            local   — source root is ./ (current project)
  platform  opencode | claude
            Determines the config directory name (.opencode or .claude)
  items     Optional filters in the form type:name
            agent:<name>    — copy agent file (name.md)
            skill:<name>    — copy entire skill directory (name/)
            command:<name>  — copy command file (name.md)
            prompt:<name>   — copy prompt file (name.md)
            When omitted, all items are copied (default behavior).

Destination mapping:
  agents/   → ~/agent-registry/agents/{platform}/
  skills/   → ~/agent-registry/skills/
  commands/ → ~/agent-registry/commands/
  prompts/  → ~/agent-registry/prompts/

Examples:
  $(basename "$0") --contributor mf local opencode
  $(basename "$0") --contributor mf local opencode agent:builder skill:research
  $(basename "$0") --contributor mf global claude agent:designer command:review
EOF
  exit 1
}

CONTRIBUTOR=""

POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --contributor)
      [ $# -lt 2 ] && { echo "Error: --contributor requires a value" >&2; exit 1; }
      CONTRIBUTOR="$2"
      shift 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

[ -z "$CONTRIBUTOR" ] && { echo "Error: --contributor is required" >&2; usage; }
sanitize_yq_key "$CONTRIBUTOR" || { echo "Error: invalid contributor key '$CONTRIBUTOR'" >&2; exit 1; }

[ $# -lt 2 ] && usage

SCOPE="$1"; shift
PLATFORM="$1"; shift

FILTERS=()
for arg in "$@"; do
  if [[ "$arg" != *":"* ]]; then
    echo "Error: invalid filter '$arg' (expected type:name, e.g. agent:builder)" >&2
    usage
  fi
  _type="${arg%%:*}"
  _name="${arg#*:}"
  case "$_type" in
    agent|skill|command|prompt) ;;
    *) echo "Error: unknown type '$_type' (expected: agent, skill, command, prompt)" >&2; usage ;;
  esac
  if ! sanitize_name "$_name"; then
    echo "Error: invalid name '$_name' (alphanumeric, dashes, underscores only)" >&2
    exit 1
  fi
  FILTERS+=("$arg")
done

case "$SCOPE" in
  global) SOURCE_ROOT="$HOME" ;;
  local)  SOURCE_ROOT="$(pwd)" ;;
  *)      echo "Error: scope must be 'global' or 'local'" >&2; usage ;;
esac

case "$PLATFORM" in
  opencode) PLATFORM_DIR=".opencode" ;;
  claude)   PLATFORM_DIR=".claude" ;;
  *)        echo "Error: platform must be 'opencode' or 'claude'" >&2; usage ;;
esac

if [ "$SCOPE" = "global" ] && [ "$PLATFORM" = "opencode" ]; then
  SOURCE_BASE="${SOURCE_ROOT}/.config/opencode"
else
  SOURCE_BASE="${SOURCE_ROOT}/${PLATFORM_DIR}"
fi

if [ ! -d "$SOURCE_BASE" ]; then
  log_fail "source directory does not exist: $SOURCE_BASE"
  exit 1
fi

COPIED=()
SKIPPED=()
FAILED=()
REGISTRY_UPDATED=()

resolve_dest() {
  local folder="$1"
  case "$folder" in
    agents)   echo "$DEST_ROOT/agents/$PLATFORM" ;;
    skills)   echo "$DEST_ROOT/skills" ;;
    commands) echo "$DEST_ROOT/commands" ;;
    prompts)  echo "$DEST_ROOT/prompts" ;;
  esac
}

get_contributor_repo() {
  local contributor="$1"
  local repo_url
  repo_url=$(yq -r ".contributors.\"$contributor\".gh-repo[0]" "$CONTRIBUTORS" 2>/dev/null)
  if [ -z "$repo_url" ] || [ "$repo_url" = "null" ]; then
    return 1
  fi
  echo "$repo_url" | sed 's|https://github.com/||' | sed 's|.git$||'
}

detect_branch() {
  local owner_repo="$1"
  [ -d "$DEST_ROOT/.git" ] || { echo "main"; return; }
  local b
  b=$(git -C "$DEST_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  [ -n "$b" ] && echo "$b" || echo "main"
}

build_source_url() {
  local item_type="$1"
  local item_name="$2"
  local repo="$3"
  local branch="$4"

  if [ "$item_type" = "agent" ]; then
    echo "https://github.com/$repo/blob/$branch/agents/$PLATFORM/$item_name.md"
  elif [ "$item_type" = "skill" ]; then
    echo "https://github.com/$repo/tree/$branch/skills/$item_name"
  elif [ "$item_type" = "command" ]; then
    echo "https://github.com/$repo/blob/$branch/commands/$item_name.md"
  elif [ "$item_type" = "prompt" ]; then
    echo "https://github.com/$repo/blob/$branch/prompts/$item_name.md"
  fi
}

update_registry_entry() {
  local item_type="$1"
  local item_name="$2"

  local section
  case "$item_type" in
    agent)   section="registry.agents" ;;
    skill)   section="registry.skills" ;;
    command) section="registry.commands" ;;
    prompt)  section="registry.prompts" ;;
  esac

  local yq_path=".$section.\"$CONTRIBUTOR\""
  if [ "$item_type" = "agent" ]; then
    yq_path="${yq_path}.\"$PLATFORM\""
  fi
  yq_path="${yq_path}.\"$item_name\""

  local existing
  existing=$(yq -r "${yq_path}.source" "$REGISTRY" 2>/dev/null || true)
  if [ -n "$existing" ] && [ "$existing" != "null" ]; then
    return 0
  fi

  local repo
  repo=$(get_contributor_repo "$CONTRIBUTOR") || { log_warn "no repo configured for contributor '$CONTRIBUTOR'"; return 1; }
  local branch
  branch=$(detect_branch "$repo")
  local source_url
  source_url=$(build_source_url "$item_type" "$item_name" "$repo" "$branch")

  yq -i "${yq_path}.source = \"$source_url\"" "$REGISTRY"
  yq -i "${yq_path}.description = \"\"" "$REGISTRY"

  REGISTRY_UPDATED+=("${item_type}:${item_name}")
}

log_banner() {
  echo -e "\n${BOLD}${CYAN}╭──────────────────────────────────────${RESET}"
  echo -e "${BOLD}${CYAN}│ Agent Registry Manager — Migrate${RESET}"
  if [ ${#FILTERS[@]} -gt 0 ]; then
    echo -e "${BOLD}${CYAN}│${RESET} ${DIM}scope: $SCOPE · platform: $PLATFORM · filters: ${#FILTERS[@]}${RESET}"
  else
    echo -e "${BOLD}${CYAN}│${RESET} ${DIM}scope: $SCOPE · platform: $PLATFORM · all items${RESET}"
  fi
  echo -e "${BOLD}${CYAN}╰──────────────────────────────────────${RESET}"
}

migrate_folder() {
  local folder="$1"
  local idx="$2"
  local total="$3"

  local src="$SOURCE_BASE/$folder"
  local dest
  dest=$(resolve_dest "$folder")

  log_step "[$idx/$total] ${BOLD}$folder${RESET}"
  log_info "source: $src"
  log_info "dest:   $dest"

  if [ ! -d "$src" ]; then
    log_warn "source folder does not exist, skipping"
    SKIPPED+=("$folder")
    return
  fi

  local item_type="${folder%s}"
  local items=()

  if [ "$item_type" = "skill" ]; then
    for dir in "$src"/*/; do
      [ -d "$dir" ] || continue
      items+=("$(basename "$dir")")
    done
  else
    for file in "$src"/*.md; do
      [ -f "$file" ] || continue
      items+=("$(basename "$file" .md)")
    done
  fi

  if [ ${#items[@]} -eq 0 ]; then
    log_warn "source folder is empty, skipping"
    SKIPPED+=("$folder")
    return
  fi

  mkdir -p "$dest"

  for name in "${items[@]}"; do
    if [ "$item_type" = "skill" ]; then
      rm -rf "${dest:?}/${name}"
      cp -r "$src/$name" "$dest"
    else
      rm -f "${dest:?}/${name}.md"
      cp "$src/$name.md" "$dest"
    fi
    update_registry_entry "$item_type" "$name" || true
  done

  log_ok "migrated ${#items[@]} item(s) from $folder"
  COPIED+=("$folder")
}

migrate_item() {
  local item_type="$1"
  local item_name="$2"
  local idx="$3"
  local total="$4"

  local label="${item_type}:${item_name}"
  local folder="${item_type}s"
  local src="$SOURCE_BASE/$folder"
  local dest
  dest=$(resolve_dest "$folder")

  log_step "[$idx/$total] ${BOLD}$label${RESET}"

  if [ "$item_type" = "skill" ]; then
    src="$src/$item_name"
    log_info "source: $src"
    log_info "dest:   $dest/$item_name"

    if [ ! -d "$src" ]; then
      log_warn "source directory does not exist, skipping"
      SKIPPED+=("$label")
      return
    fi

    mkdir -p "$dest"
    rm -rf "${dest:?}/${item_name}"
    if cp -r "$src" "$dest"; then
      log_ok "migrated skill '$item_name'"
      update_registry_entry "$item_type" "$item_name" || true
      COPIED+=("$label")
    else
      log_fail "failed to copy skill '$item_name'"
      FAILED+=("$label")
    fi
  else
    src="$src/${item_name}.md"
    log_info "source: $src"
    log_info "dest:   $dest/${item_name}.md"

    if [ ! -f "$src" ]; then
      log_warn "source file does not exist, skipping"
      SKIPPED+=("$label")
      return
    fi

    mkdir -p "$dest"
    rm -f "${dest:?}/${item_name}.md"
    if cp "$src" "$dest/${item_name}.md"; then
      log_ok "migrated $item_type '$item_name'"
      update_registry_entry "$item_type" "$item_name" || true
      COPIED+=("$label")
    else
      log_fail "failed to copy $item_type '$item_name'"
      FAILED+=("$label")
    fi
  fi
}

log_banner

if [ ${#FILTERS[@]} -eq 0 ]; then
  FOLDERS=("agents" "skills" "commands" "prompts")
  TOTAL=${#FOLDERS[@]}
  idx=0
  for folder in "${FOLDERS[@]}"; do
    idx=$((idx + 1))
    migrate_folder "$folder" "$idx" "$TOTAL"
  done
else
  TOTAL=${#FILTERS[@]}
  idx=0
  for filter in "${FILTERS[@]}"; do
    idx=$((idx + 1))
    _type="${filter%%:*}"
    _name="${filter#*:}"
    migrate_item "$_type" "$_name" "$idx" "$TOTAL"
  done
fi

echo -e "\n${BOLD}── Summary ──${RESET}"
if [ ${#COPIED[@]} -gt 0 ]; then
  echo -e "  ${GREEN}✔ Copied:${RESET}   ${COPIED[*]}"
fi
if [ ${#REGISTRY_UPDATED[@]} -gt 0 ]; then
  echo -e "  ${BLUE}◉ Registry:${RESET} ${REGISTRY_UPDATED[*]}"
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
