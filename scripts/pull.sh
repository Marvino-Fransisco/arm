#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <repository>

Pull changes from the arm or agent-registry repository.

Arguments:
  repository    arm | registry

Examples:
  $(basename "$0") arm
  $(basename "$0") registry
EOF
  exit 1
}

[ $# -ne 1 ] && usage

REPOSITORY="$1"

case "$REPOSITORY" in
  arm)
    WORK_DIR="$ROOT_DIR"
    LABEL="arm"
    ;;
  registry)
    WORK_DIR="$HOME/agent-registry"
    LABEL="agent-registry"
    ;;
  *)
    log_fail "invalid repository '$REPOSITORY'. Use 'arm' or 'registry'."
    exit 1
    ;;
esac

if [ ! -d "$WORK_DIR/.git" ]; then
  log_fail "'$WORK_DIR' is not a git repository"
  exit 1
fi

require_cmd git

REMOTE_URL=$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null || echo "unknown")

echo -e "\n${BOLD}${CYAN}╭──────────────────────────────────────${RESET}"
echo -e "${BOLD}${CYAN}│ Agent Registry Manager — Pull${RESET}"
echo -e "${BOLD}${CYAN}│${RESET} ${DIM}repository: $LABEL · dir: $WORK_DIR${RESET}"
echo -e "${BOLD}${CYAN}╰──────────────────────────────────────${RESET}"

LOCAL_HASH=$(git -C "$WORK_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
LOCAL_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

log_step "Current state — ${BOLD}$LABEL${RESET} ($LOCAL_BRANCH)"
log_info "local:  $LOCAL_HASH"
log_info "remote: $REMOTE_URL"

log_step "Fetching from origin"
git -C "$WORK_DIR" fetch origin

BEHIND=$(git -C "$WORK_DIR" log HEAD..origin/"$LOCAL_BRANCH" --oneline 2>/dev/null || true)
if [ -z "$BEHIND" ]; then
  log_ok "already up to date — no new commits"
  echo ""
  exit 0
fi

COMMIT_COUNT=$(echo "$BEHIND" | wc -l | tr -d ' ')

log_step "New commits available (${BOLD}${COMMIT_COUNT} behind${RESET})"
echo "$BEHIND" | sed 's/^/    /'

echo ""
echo -ne "  ${BOLD}Pull from origin? [y/N]${RESET} "
read -r CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  log_warn "aborted — no changes pulled"
  echo ""
  exit 0
fi

log_step "Pulling from origin"
git -C "$WORK_DIR" pull --ff-only origin "$LOCAL_BRANCH"
log_ok "pulled"

NEW_HASH=$(git -C "$WORK_DIR" rev-parse --short HEAD)

echo -e "\n${BOLD}── Summary ──${RESET}"
echo -e "  ${GREEN}✔${RESET} $LABEL ← origin"
echo -e "  ${DIM}$LOCAL_HASH → $NEW_HASH · $COMMIT_COUNT commit(s) pulled${RESET}"
echo -e "  ${DIM}$REMOTE_URL${RESET}"
echo ""
