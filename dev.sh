#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_name="$(basename -- "${repo_root}")"

# Normalize the repository name for use as a tmux session name.
session_name="$(printf '%s' "${repo_name}" | tr -c '[:alnum:]_-' '-')"

mode="${1:-dev}"

green=""
red=""
reset=""

usage() {
  printf 'Usage: %s [rebuild|shell]\n' "${0}"
}

parse_arguments() {
  if (($# > 1)); then
    usage >&2
    exit 2
  fi

  case "${mode}" in
  dev | rebuild | shell)
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf 'Unknown command: %s\n' "${mode}" >&2
    usage >&2
    exit 2
    ;;
  esac
}

init_colors() {
  # stdout has a TTY, so ANSI colors are safe to use.
  if [[ -t 1 ]]; then
    green=$'\033[32m'
    red=$'\033[31m'
    reset=$'\033[0m'
  fi
}

check_passed() {
  printf '  %s✓%s %s\n' "${green}" "${reset}" "$1"
}

check_failed() {
  printf '  %s✗%s %s\n' "${red}" "${reset}" "$1" >&2
  return 1
}

check_command() {
  local command_name="$1"

  if command -v "${command_name}" >/dev/null 2>&1; then
    check_passed "${command_name}"
  else
    check_failed "${command_name}"
  fi
}

check_file() {
  local file_path="$1"
  local description="$2"

  if [[ -f "${file_path}" ]]; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_directory() {
  local directory="$1"
  local description="$2"

  if [[ -d "${directory}/.git" ]]; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

ensure_podman_socket() {
  local podman_socket

  if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    check_failed "XDG_RUNTIME_DIR"
    return
  fi

  check_passed "XDG_RUNTIME_DIR"

  podman_socket="${XDG_RUNTIME_DIR}/podman/podman.sock"

  if [[ -S "${podman_socket}" ]]; then
    check_passed "Podman socket"
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --user start podman.socket >/dev/null 2>&1 || true
  fi

  if [[ -S "${podman_socket}" ]]; then
    check_passed "Podman socket"
  else
    check_failed "Podman socket: ${podman_socket}"
  fi
}

verify_environment() {
  local status=0

  echo "Verifying environment"

  init_colors

  check_command tmux || status=1
  check_command podman || status=1
  check_command devcontainer || status=1

  check_file \
    "${repo_root}/.devcontainer/devcontainer.json" \
    ".devcontainer/devcontainer.json" ||
    status=1

  ensure_podman_socket || status=1

  check_directory "${repo_root}/../homelab" "homelab repository" || status=1
  check_directory "${repo_root}/../local-platform" "local-platform repository" || status=1
  check_directory "${repo_root}/../local-environments" "local-environments repository" || status=1

  if ((status != 0)); then
    echo >&2
    echo "Environment verification failed." >&2
  fi

  return "${status}"
}

open_troubleshooting_shell() {
  local message="$1"

  echo
  printf '%s✗%s %s\n' \
    "${red}" \
    "${reset}" \
    "${message}" >&2

  echo
  echo "Opening a host shell for troubleshooting."
  echo

  exec "${SHELL:-/bin/bash}" -l
}

open_existing_devcontainer_shell() {
  echo
  echo "Opening additional shell in ${repo_name}"
  echo

  if ! exec devcontainer exec \
    --workspace-folder "${repo_root}" \
    --docker-path podman \
    bash --login; then
    open_troubleshooting_shell \
      "Development container is not running. Start it with ./dev.sh"
  fi
}

enter_devcontainer() {
  local -a up_arguments=(
    --workspace-folder "${repo_root}"
    --docker-path podman
  )

  mkdir -p "${HOME}/.config/nvim"

  if [[ "${mode}" == "rebuild" ]]; then
    echo "Rebuilding development container"
    up_arguments+=(--remove-existing-container)
  else
    echo "Starting development container"
  fi

  if ! devcontainer up "${up_arguments[@]}"; then
    open_troubleshooting_shell \
      "Failed to start development container"
  fi

  echo
  echo "Entering ${repo_name}"
  echo

  if ! exec devcontainer exec \
    --workspace-folder "${repo_root}" \
    --docker-path podman \
    bash --login; then
    open_troubleshooting_shell \
      "Failed to enter development container"
  fi
}

start_tmux_session() {
  # This branch executes inside the repository-specific tmux session.
  if [[ "${DEV_SH_INSIDE_SESSION:-}" == "1" ]]; then
    enter_devcontainer
  fi

  # A rebuild starts with a fresh repository-specific tmux session.
  if [[ "${mode}" == "rebuild" ]] &&
    tmux has-session -t "=${session_name}" 2>/dev/null; then
    echo "Stopping existing tmux session: ${session_name}"
    tmux kill-session -t "=${session_name}"
  fi

  # Reuse an existing repository session during normal startup.
  if tmux has-session -t "=${session_name}" 2>/dev/null; then
    if [[ -n "${TMUX:-}" ]]; then
      exec tmux switch-client -t "=${session_name}"
    else
      exec tmux attach-session -t "=${session_name}"
    fi
  fi

  # Start this script again as the first process in the new tmux session.
  local session_command

  printf -v session_command \
    'DEV_SH_INSIDE_SESSION=1 %q %q' \
    "${repo_root}/dev.sh" \
    "${mode}"

  if [[ -n "${TMUX:-}" ]]; then
    tmux new-session \
      -d \
      -s "${session_name}" \
      -c "${repo_root}" \
      "${session_command}"

    exec tmux switch-client -t "=${session_name}"
  else
    exec tmux new-session \
      -s "${session_name}" \
      -c "${repo_root}" \
      "${session_command}"
  fi
}

parse_arguments "$@"

if ! verify_environment; then
  exit 1
fi

echo

if [[ "${mode}" == "shell" ]]; then
  open_existing_devcontainer_shell
fi

start_tmux_session
