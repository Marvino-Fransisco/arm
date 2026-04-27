#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/utils.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") <repository>

Push changes to the arm or agent-registry repository.

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
echo -e "${BOLD}${CYAN}│ Agent Registry Manager — Push${RESET}"
echo -e "${BOLD}${CYAN}│${RESET} ${DIM}repository: $LABEL · dir: $WORK_DIR${RESET}"
echo -e "${BOLD}${CYAN}╰──────────────────────────────────────${RESET}"

log_step "Staging all changes in ${BOLD}$LABEL${RESET}"
git -C "$WORK_DIR" add -A

LOCAL_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

STAGED=$(git -C "$WORK_DIR" diff --cached --name-only)
UNSTAGED=$(git -C "$WORK_DIR" diff --name-only)
AHEAD=$(git -C "$WORK_DIR" log origin/"$LOCAL_BRANCH"..HEAD --oneline 2>/dev/null || true)

if [ -z "$STAGED" ] && [ -z "$UNSTAGED" ]; then
  if [ -n "$AHEAD" ]; then
    COMMIT_COUNT=$(echo "$AHEAD" | wc -l | tr -d ' ')
    log_info "nothing new to commit, but ${COMMIT_COUNT} commit(s) ahead of origin/$LOCAL_BRANCH"

    log_step "Commits to be pushed (${BOLD}${COMMIT_COUNT} ahead${RESET})"
    echo "$AHEAD" | sed 's/^/    /'

    echo ""
    echo -ne "  ${BOLD}Push to origin? [y/N]${RESET} "
    read -r CONFIRM

    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
      log_warn "aborted — commits not pushed"
      echo ""
      exit 0
    fi

    log_step "Pushing to origin"
    git -C "$WORK_DIR" push origin HEAD
    log_ok "pushed"

    COMMIT_HASH=$(git -C "$WORK_DIR" rev-parse --short HEAD)

    echo -e "\n${BOLD}── Summary ──${RESET}"
    echo -e "  ${GREEN}✔${RESET} $LABEL → origin"
    echo -e "  ${DIM}$COMMIT_HASH · $COMMIT_COUNT commit(s) pushed${RESET}"
    echo -e "  ${DIM}$REMOTE_URL${RESET}"
    echo ""
    exit 0
  fi

  log_ok "nothing to commit — working tree clean and up to date"
  echo ""
  exit 0
fi

FILE_COUNT=$(echo "$STAGED" | wc -l | tr -d ' ')

SENSITIVE=$(echo "$STAGED" | grep -iE '\.(env|key|pem|p12)$|(credential|secret|password)s?\.' || true)
if [ -n "$SENSITIVE" ]; then
  log_warn "Potentially sensitive files staged:"
  echo "$SENSITIVE" | sed 's/^/    /'
  echo ""
fi

STATS=$(git -C "$WORK_DIR" diff --cached --stat)

log_step "Changes to be committed (${BOLD}${FILE_COUNT} files${RESET})"
echo "$STATS" | sed 's/^/    /'

echo ""
echo -ne "  ${BOLD}Push to origin? [y/N]${RESET} "
read -r CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  log_warn "aborted — changes remain staged"
  echo ""
  exit 0
fi

COMMIT_MSG="chore: update $LABEL — $FILE_COUNT files changed"

log_step "Committing"
git -C "$WORK_DIR" commit -m "$COMMIT_MSG"
log_ok "committed"

log_step "Pushing to origin"
git -C "$WORK_DIR" push origin HEAD
log_ok "pushed"

COMMIT_HASH=$(git -C "$WORK_DIR" rev-parse --short HEAD)

echo -e "\n${BOLD}── Summary ──${RESET}"
echo -e "  ${GREEN}✔${RESET} $LABEL → origin"
echo -e "  ${DIM}$COMMIT_HASH · $COMMIT_MSG${RESET}"
echo -e "  ${DIM}$REMOTE_URL${RESET}"
echo ""
