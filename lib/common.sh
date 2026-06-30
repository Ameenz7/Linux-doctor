#!/usr/bin/env bash

if [[ -n "${LINUX_DOCTOR_COMMON_LOADED:-}" ]]; then
  return 0
fi
LINUX_DOCTOR_COMMON_LOADED=1

RESET=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
BLUE=$'\e[34m'
CYAN=$'\e[36m'
GREEN=$'\e[32m'
YELLOW=$'\e[33m'
RED=$'\e[31m'
GRAY=$'\e[38;5;250m'

term_cols() {
  local cols=80
  if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    cols=$(tput cols 2>/dev/null || echo 80)
  fi
  printf '%s' "${cols:-80}"
}

centered_line() {
  local line="$1"
  local width len
  width=$(term_cols)
  len=${#line}

  if (( len >= width )); then
    printf '%s' "$line"
  else
    printf '%*s%s' $(((width - len) / 2)) '' "$line"
  fi
}

print_center() {
  local line="$1"
  local color="${2:-}"
  printf '%b%s%b\n' "$color" "$(centered_line "$line")" "$RESET"
}

print_banner() {
  local lines=(
    '██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗'
    '██║     ██║████╗  ██║██║   ██║╚██╗██╔╝'
    '██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ '
    '██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ '
    '███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗'
    '╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝'
    '██████╗  ██████╗  ██████╗████████╗ ██████╗ ██████╗ '
    '██╔══██╗██╔═══██╗██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗'
    '██║  ██║██║   ██║██║        ██║   ██║   ██║██████╔╝'
    '██║  ██║██║   ██║██║        ██║   ██║   ██║██╔══██╗'
    '██████╔╝╚██████╔╝╚██████╗   ██║   ╚██████╔╝██║  ██║'
    '╚═════╝  ╚═════╝  ╚═════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝'
  )

  echo
  for line in "${lines[@]}"; do
    print_center "$line" "$GRAY"
  done
  print_center 'linux-doctor' "$DIM"
  echo
}

rule() {
  local width
  width=$(term_cols)
  printf '%b' "$DIM"
  printf '%*s\n' "$width" '' | tr ' ' '-'
  printf '%b' "$RESET"
}

section() {
  echo
  rule
  printf '%b%s%b\n' "$BOLD$CYAN" "$1" "$RESET"
  rule
}

info() {
  printf '%b[INFO]%b %s\n' "$BLUE" "$RESET" "$1"
}

success() {
  printf '%b[ OK ]%b %s\n' "$GREEN" "$RESET" "$1"
}

warn() {
  printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$1"
}

critical() {
  printf '%b[CRIT]%b %s\n' "$RED" "$RESET" "$1"
}

dim() {
  printf '%b%s%b\n' "$DIM" "$1" "$RESET"
}

pause() {
  if [[ -t 0 ]]; then
    echo
    read -r -p 'Press Enter to continue...' _
  fi
}

issue() {
  local severity="$1"
  local problem="$2"
  local why="$3"
  local fix="$4"
  local commands="$5"

  case "$severity" in
    INFO) info "$problem" ;;
    OK) success "$problem" ;;
    WARN) warn "$problem" ;;
    CRIT) critical "$problem" ;;
    *) printf '%s\n' "$problem" ;;
  esac

  [[ -n "$why" ]] && printf '  Why: %s\n' "$why"
  [[ -n "$fix" ]] && printf '  Fix: %s\n' "$fix"

  if [[ -n "$commands" ]]; then
    printf '  Commands:\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] && printf '    %s\n' "$line"
    done <<< "$commands"
  fi

  echo
}
