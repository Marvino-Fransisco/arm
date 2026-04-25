#!/usr/bin/env bash

# ======================
# Colors
# ======================

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
RESET='\033[0m'

# ======================
# Logging functions
# ======================

log_step() {
  echo -e "\n${BOLD}${BLUE}▸${RESET} $1"
}

log_ok() {
  echo -e "  ${GREEN}✔${RESET} $1"
}

log_fail() {
  echo -e "  ${RED}✘${RESET} $1" >&2
}

log_warn() {
  echo -e "  ${YELLOW}⚠${RESET} $1"
}

log_info() {
  echo -e "  ${DIM}$1${RESET}"
}

