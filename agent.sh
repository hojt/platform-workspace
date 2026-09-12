#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_name="$(basename -- "${repo_root}")"
agent_devcontainer_config="${repo_root}/.devcontainer/agent/devcontainer.json"

mode="dev"
entrypoint="opencode"

green=""
red=""
reset=""

usage() {
  printf 'Usage: %s [rebuild] [shell]\n' "${0}"
}

parse_arguments() {
  if (($# > 2)); then
    usage >&2
    exit 2
  fi

  local argument

  for argument in "$@"; do
    case "${argument}" in
    rebuild)
      if [[ "${mode}" == "rebuild" ]]; then
        printf 'Duplicate command: rebuild\n' >&2
        usage >&2
        exit 2
      fi
      mode="rebuild"
      ;;
    shell)
      if [[ "${entrypoint}" == "shell" ]]; then
        printf 'Duplicate command: shell\n' >&2
        usage >&2
        exit 2
      fi
      entrypoint="shell"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown command: %s\n' "${argument}" >&2
      usage >&2
      exit 2
      ;;
    esac
  done
}

init_colors() {
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

verify_host_environment() {
  local status=0

  echo "Verifying host environment"

  init_colors

  check_command tmux || status=1
  check_command podman || status=1
  check_command devcontainer || status=1

  check_file \
    "${agent_devcontainer_config}" \
    ".devcontainer/agent/devcontainer.json" ||
    status=1

  check_directory "${repo_root}/../homelab" "homelab repository" || status=1
  check_directory "${repo_root}/../local-platform" "local-platform repository" || status=1
  check_directory "${repo_root}/../local-environments" "local-environments repository" || status=1

  if ((status != 0)); then
    echo >&2
    echo "Host environment verification failed." >&2
  fi

  return "${status}"
}

agent_exec() {
  devcontainer exec \
    --workspace-folder "${repo_root}" \
    --config "${agent_devcontainer_config}" \
    --docker-path podman \
    "$@"
}

check_agent_repository() {
  local directory="$1"
  local description="$2"

  if agent_exec test -d "${directory}/.git"; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_agent_path_absent() {
  local path="$1"
  local description="$2"

  if agent_exec test ! -e "${path}"; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_agent_socket_absent() {
  local path="$1"
  local description="$2"

  if agent_exec test ! -S "${path}"; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_agent_env_absent() {
  local variable="$1"
  local description="$2"

  if ! agent_exec printenv "${variable}" >/dev/null 2>&1; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

verify_agent_environment() {
  local status=0

  echo
  echo "Verifying agent environment"

  init_colors

  check_agent_repository \
    "/workspace/repos/homelab" \
    "homelab repository is available" ||
    status=1

  check_agent_repository \
    "/workspace/repos/local-platform" \
    "local-platform repository is available" ||
    status=1

  check_agent_repository \
    "/workspace/repos/local-environments" \
    "local-environments repository is available" ||
    status=1

  check_agent_socket_absent \
    "/run/podman/podman.sock" \
    "host Podman socket is not exposed" ||
    status=1

  check_agent_path_absent \
    "/home/developer/.kube/config" \
    "host Kubernetes configuration is not exposed" ||
    status=1

  check_agent_path_absent \
    "/home/developer/.gitconfig" \
    "host Git configuration is not exposed" ||
    status=1

  check_agent_env_absent \
    "CONTAINER_HOST" \
    "CONTAINER_HOST is not configured" ||
    status=1

  check_agent_env_absent \
    "DOCKER_HOST" \
    "DOCKER_HOST is not configured" ||
    status=1

  check_agent_env_absent \
    "KUBECONFIG" \
    "KUBECONFIG is not configured" ||
    status=1

  if ((status != 0)); then
    echo >&2
    echo "Agent environment verification failed." >&2
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

enter_devcontainer() {
  local -a up_arguments=(
    --workspace-folder "${repo_root}"
    --config "${agent_devcontainer_config}"
    --docker-path podman
  )

  if [[ "${mode}" == "rebuild" ]]; then
    echo "Rebuilding agent container"
    up_arguments+=(--remove-existing-container)
  else
    echo "Starting agent container"
  fi

  if ! devcontainer up "${up_arguments[@]}"; then
    open_troubleshooting_shell \
      "Failed to start agent container"
  fi

  if ! verify_agent_environment; then
    open_troubleshooting_shell \
      "Agent environment does not match expected containment"
  fi

  echo

  case "${entrypoint}" in
  opencode)
    echo "Starting OpenCode in ${repo_name}"
    echo

    exec devcontainer exec \
      --workspace-folder "${repo_root}" \
      --config "${agent_devcontainer_config}" \
      --docker-path podman \
      opencode
    ;;
  shell)
    echo "Opening shell in ${repo_name} agent container"
    echo

    exec devcontainer exec \
      --workspace-folder "${repo_root}" \
      --config "${agent_devcontainer_config}" \
      --docker-path podman \
      bash -l
    ;;
  esac
}

start_tmux_session() {
  local session_name

  if [[ "${entrypoint}" == "shell" ]]; then
    session_name="$(printf '%s-agent-shell' "${repo_name}" | tr -c '[:alnum:]_-' '-')"
  else
    session_name="$(printf '%s-agent' "${repo_name}" | tr -c '[:alnum:]_-' '-')"
  fi

  if [[ "${AGENT_SH_INSIDE_SESSION:-}" == "1" ]]; then
    enter_devcontainer
  fi

  if [[ "${mode}" == "rebuild" ]] &&
    tmux has-session -t "=${session_name}" 2>/dev/null; then
    echo "Stopping existing tmux session: ${session_name}"
    tmux kill-session -t "=${session_name}"
  fi

  if tmux has-session -t "=${session_name}" 2>/dev/null; then
    if [[ -n "${TMUX:-}" ]]; then
      exec tmux switch-client -t "=${session_name}"
    else
      exec tmux attach-session -t "=${session_name}"
    fi
  fi

  local -a script_arguments=()

  if [[ "${mode}" == "rebuild" ]]; then
    script_arguments+=(rebuild)
  fi

  if [[ "${entrypoint}" == "shell" ]]; then
    script_arguments+=(shell)
  fi

  local session_command="AGENT_SH_INSIDE_SESSION=1"

  printf -v session_command \
    '%s %q' \
    "${session_command}" \
    "${repo_root}/agent.sh"

  local argument

  for argument in "${script_arguments[@]}"; do
    printf -v session_command \
      '%s %q' \
      "${session_command}" \
      "${argument}"
  done

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

if ! verify_host_environment; then
  exit 1
fi

echo

start_tmux_session
