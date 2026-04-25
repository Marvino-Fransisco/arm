#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

OUTPUT="${1:-$ROOT_DIR/registry.md}"
sanitize_md() {
  local s="$1"
  local bt='`'
  s="${s//|/\\|}"
  s="${s//$bt/\\$bt}"
  s="${s//\[/\\[}"
  s="${s//\]/\\]}"
  echo "$s"
}

TMP_OUTPUT=$(mktemp)
ADDED_LOG=$(mktemp)
REMOVED_LOG=$(mktemp)
trap 'rm -f "$TMP_OUTPUT" "$ADDED_LOG" "$REMOVED_LOG"' EXIT

cat > "$TMP_OUTPUT" <<'HEADER'
# Registry

This document is auto-generated from `registry.yaml`. Do not edit manually.

<!-- regenerate: bash scripts/parse-registry.sh [output path] -->

HEADER

echo -e "## Agents\n" >> "$TMP_OUTPUT"

agent_count=0
has_agents=false

for contributor in $(yq '.registry.agents | keys | .[]' "$REGISTRY" 2>/dev/null); do
  for platform in $(yq ".registry.agents.\"$contributor\" | keys | .[]" "$REGISTRY" 2>/dev/null); do
    names=$(yq ".registry.agents.\"$contributor\".\"$platform\" | keys | .[]" "$REGISTRY" 2>/dev/null) || continue

    [ -z "$names" ] && continue

    for name in $names; do
      [ "$has_agents" = false ] && { echo "| Name | Platform | Contributor |" >> "$TMP_OUTPUT"; echo "|------|----------|-------------|" >> "$TMP_OUTPUT"; has_agents=true; }

      echo "| \`$(sanitize_md "$name")\` | \`$(sanitize_md "$platform")\` | \`$(sanitize_md "$contributor")\` |" >> "$TMP_OUTPUT"
      agent_count=$((agent_count + 1))
    done
  done
done

if [ "$has_agents" = false ]; then
  echo "_No agents registered._" >> "$TMP_OUTPUT"
fi

echo -e "\n## Skills\n" >> "$TMP_OUTPUT"

skill_count=0
has_skills=false

for contributor in $(yq '.registry.skills | keys | .[]' "$REGISTRY" 2>/dev/null); do
  names=$(yq ".registry.skills.\"$contributor\" | keys | .[]" "$REGISTRY" 2>/dev/null) || continue

  [ -z "$names" ] && continue

  for name in $names; do
    [ "$has_skills" = false ] && { echo "| Name | Contributor |" >> "$TMP_OUTPUT"; echo "|------|-------------|" >> "$TMP_OUTPUT"; has_skills=true; }

    echo "| \`$(sanitize_md "$name")\` | \`$(sanitize_md "$contributor")\` |" >> "$TMP_OUTPUT"
    skill_count=$((skill_count + 1))
  done
done

if [ "$has_skills" = false ]; then
  echo "_No skills registered._" >> "$TMP_OUTPUT"
fi

echo -e "\n---\n" >> "$TMP_OUTPUT"
echo "_Last updated: $(date '+%Y-%m-%d %H:%M') • $agent_count agents • $skill_count skills_" >> "$TMP_OUTPUT"

if [ -f "$OUTPUT" ]; then
  DIFF_OLD=$(grep -v '_Last updated:' "$OUTPUT" || true)
  DIFF_NEW=$(grep -v '_Last updated:' "$TMP_OUTPUT" || true)

  if [ "$DIFF_OLD" = "$DIFF_NEW" ]; then
    log_ok "No changes detected, $OUTPUT is up to date"
    log_info "$agent_count agents, $skill_count skills"
    exit 0
  fi

  OLD_ROWS=$(grep '^|' "$OUTPUT" | grep -v '^| Name' | grep -v '^|--' || true)
  NEW_ROWS=$(grep '^|' "$TMP_OUTPUT" | grep -v '^| Name' | grep -v '^|--' || true)

  while IFS= read -r row; do
    [ -z "$row" ] && continue
    if ! echo "$NEW_ROWS" | grep -qF "$row"; then
      echo "$row" >> "$REMOVED_LOG"
    fi
  done <<< "$OLD_ROWS"

  while IFS= read -r row; do
    [ -z "$row" ] && continue
    if ! echo "$OLD_ROWS" | grep -qF "$row"; then
      echo "$row" >> "$ADDED_LOG"
    fi
  done <<< "$NEW_ROWS"
fi

mv "$TMP_OUTPUT" "$OUTPUT"
log_ok "Generated $OUTPUT"
log_info "$agent_count agents, $skill_count skills"

if [ -f "$ADDED_LOG" ] && [ -s "$ADDED_LOG" ]; then
  added_count=$(wc -l < "$ADDED_LOG" | tr -d ' ')
  echo ""
  echo -e "${GREEN}${BOLD}Added ($added_count):${RESET}"
  while IFS= read -r row; do
    log_ok "$row"
  done < "$ADDED_LOG"
fi

if [ -f "$REMOVED_LOG" ] && [ -s "$REMOVED_LOG" ]; then
  removed_count=$(wc -l < "$REMOVED_LOG" | tr -d ' ')
  echo ""
  echo -e "${RED}${BOLD}Removed ($removed_count):${RESET}"
  while IFS= read -r row; do
    log_fail "$row"
  done < "$REMOVED_LOG"
fi
