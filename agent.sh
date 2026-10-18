#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_name="$(basename -- "${repo_root}")"
agent_workspace="/workspaces/${repo_name}"
agent_devcontainer_config="${repo_root}/.devcontainer/agent/devcontainer.json"
agent_network="${repo_name}-agent"
agent_egress_network="${repo_name}-agent-egress"
agent_proxy="${repo_name}-agent-proxy"
agent_proxy_dir="${repo_root}/.devcontainer/agent/proxy"

mode="${1:-dev}"
agent_tool="opencode"

green=""
red=""
yellow=""
reset=""

usage() {
  printf 'Usage: %s [rebuild|shell|proxy-log|claude]\n' "${0}"
  printf '  PROXY_LOG_SINCE=<time>  limit proxy-log (e.g. -1h, today)\n'
}

parse_arguments() {
  if (($# > 1)); then
    usage >&2
    exit 2
  fi

  case "${mode}" in
  dev | rebuild | shell | proxy-log)
    ;;
  claude)
    agent_tool="claude"
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
  if [[ -t 1 ]]; then
    green=$'\033[32m'
    red=$'\033[31m'
    yellow=$'\033[33m'
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

check_host_repository() {
  local directory="$1"
  local description="$2"

  if [[ -d "${directory}/.git" ]]; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_directory() {
  local directory_path="$1"
  local description="$2"

  if [[ -d "${directory_path}" ]]; then
    check_passed "${description}"
  else
    check_failed "${description} (create with: mkdir -m 700 -p ${directory_path})"
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

  check_host_repository "${repo_root}/../homelab" "homelab repository" || status=1
  check_host_repository "${repo_root}/../local-platform" "local-platform repository" || status=1
  check_host_repository "${repo_root}/../local-environments" "local-environments repository" || status=1

  check_directory \
    "${HOME}/.local/share/claude-agent" \
    "Claude code login directory" ||
    status=1

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

check_agent_path_readonly() {
  local path="$1"
  local description="$2"

  if agent_exec test ! -w "${path}"; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_agent_path_writable() {
  local path="$1"
  local description="$2"

  if agent_exec test -w "${path}"; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_agent_mountpoint() {
  local path="$1"
  local description="$2"

  if agent_exec mountpoint -q "${path}"; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_agent_command_absent() {
  local command_name="$1"
  local description="$2"

  if ! agent_exec sh -c "command -v ${command_name}" >/dev/null 2>&1; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_agent_cannot_escalate() {
  local description="$1"

  if ! agent_exec sudo -n true >/dev/null 2>&1; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

check_agent() {
  local description="$1"
  shift

  if agent_exec "$@" >/dev/null 2>&1; then
    check_passed "${description}"
  else
    check_failed "${description}"
  fi
}

warn_agent() {
  local description="$1"
  shift

  if agent_exec "$@" >/dev/null 2>&1; then
    check_passed "${description}"
  else
    printf '  %s!%s %s\n' "${yellow}" "${reset}" "${description}" >&2
  fi
}

verify_agent_environment() {
  local status=0

  echo
  echo "Verifying agent environment"

  init_colors

  if ! check_agent_repository \
    "${agent_workspace}" \
    "${repo_name} repository is available"; then
    echo >&2
    echo "Cannot verify the agent environment." >&2
    return 1
  fi

  local repo
  for repo in homelab local-platform local-environments; do
    check_agent_repository \
      "${agent_workspace}/repos/${repo}" \
      "${repo} repository is available" ||
      status=1
  done

  check_agent "direct internet access is blocked" \
    sh -c '! curl --noproxy "*" --silent --max-time 5 --output /dev/null https://example.com' ||
    status=1

  check_agent "egress proxy is reachable" \
    curl --silent --max-time 10 --output /dev/null https://models.opencode.ai ||
    status=1

  check_agent "hosts outside the allowlist are denied" \
    sh -c '! curl --silent --max-time 10 --output /dev/null https://example.com' ||
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

  check_agent_env_absent \
    "SSH_AUTH_SOCK" \
    "SSH agent is not forwarded" ||
    status=1

  check_agent "no credential-like environment variables" \
    sh -c '! env | cut -d= -f1 | grep -Eiq "token|secret|passw|api_?key|credential|auth"' ||
    status=1

  local protected_path
  for protected_path in \
    . \
    .devcontainer \
    .git \
    AGENTS.md \
    CLAUDE.md \
    Taskfile.yml \
    agent.sh \
    dev.sh \
    opencode.json \
    repos/homelab \
    repos/homelab/.git \
    repos/local-platform \
    repos/local-platform/.git \
    repos/local-environments \
    repos/local-environments/.git; do
    check_agent_path_readonly \
      "${agent_workspace}/${protected_path}" \
      "${protected_path} is read-only" ||
      status=1
  done

  local writable_path
  # shellcheck disable=SC2043 # More writable paths may be added.
  for writable_path in \
    repos/homelab/docs; do
    check_agent_path_writable \
      "${agent_workspace}/${writable_path}" \
      "${writable_path} is writable" ||
      status=1
  done

  check_agent_command_absent podman "podman is not installed" || status=1
  check_agent_cannot_escalate "privilege escalation is not possible" || status=1

  local isolated_path
  for isolated_path in \
    .opencode \
    .claude \
    repos/local-platform/.local \
    repos/local-environments/.local; do
    check_agent_mountpoint \
      "${agent_workspace}/${isolated_path}" \
      "${isolated_path} is isolated" ||
      status=1
  done

  local hidden_path
  for hidden_path in \
    repos/local-platform/.local \
    repos/local-environments/.local; do
    # shellcheck disable=SC2016
    check_agent "${hidden_path} is hidden" \
      sh -c '[ -z "$(ls -A "$1")" ]' _ "${agent_workspace}/${hidden_path}" ||
      status=1
  done

  check_agent "no new privileges" \
    grep -qE '^NoNewPrivs:[[:space:]]+1$' /proc/self/status || status=1

  check_agent "all capabilities dropped" \
    grep -qE '^CapBnd:[[:space:]]+0+$' /proc/self/status || status=1

  # Dev Container CLI always adds --security-opt label=disable for Podman.
  # See ADR-0010 in hojt/homelab
  warn_agent "SELinux confinement is active" \
    sh -c 'grep -q ":container_t:" /proc/self/attr/current'

  # shellcheck disable=SC2016
  check_agent "memory limit is set" \
    sh -c '[ "$(cat /sys/fs/cgroup/memory.max)" != max ]' || status=1

  # shellcheck disable=SC2016
  check_agent "process limit is set" \
    sh -c '[ "$(cat /sys/fs/cgroup/pids.max)" != max ]' || status=1

  # shellcheck disable=SC2016
  check_agent "only this workspace is mounted" \
    sh -c '[ "$(ls -A /workspaces)" = "$1" ]' _ "${repo_name}" || status=1

  check_agent "Claude Code managed settings are in place" \
    test -f /etc/claude-code/managed-settings.json ||
    status=1

  if ((status != 0)); then
    echo >&2
    echo "Agent environment verification failed." >&2
  fi

  return "${status}"
}

ensure_mount_points() {
  mkdir -p \
    "${repo_root}/repos/homelab" \
    "${repo_root}/repos/local-platform" \
    "${repo_root}/repos/local-environments" \
    "${repo_root}/../local-platform/.local" \
    "${repo_root}/../local-environments/.local"
}

ensure_agent_network() {
  if ! podman network exists "${agent_network}"; then
    echo "Creating internal network ${agent_network}"
    podman network create --internal "${agent_network}" >/dev/null
  fi

  if ! podman network exists "${agent_egress_network}"; then
    echo "Creating egress network ${agent_egress_network}"
    podman network create "${agent_egress_network}" >/dev/null
  fi
}

start_agent_proxy() {
  echo "Starting egress proxy ${agent_proxy}"

  podman build \
    --quiet \
    --tag "${agent_proxy}" \
    "${agent_proxy_dir}" >/dev/null

  podman run \
    --detach \
    --replace \
    --name "${agent_proxy}" \
    --log-driver=journald \
    --network "${agent_egress_network}" \
    --network "${agent_network}" \
    --read-only \
    --cap-drop=ALL \
    --security-opt=no-new-privileges \
    --memory=256m \
    --pids-limit=128 \
    "${agent_proxy}" >/dev/null
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

open_existing_agent_shell() {
  if ! verify_agent_environment; then
    open_troubleshooting_shell \
      "Agent container is not running or does not match expected containment. Start it with ./agent.sh"
  fi

  echo
  echo "Opening additional shell in ${repo_name} agent container"
  echo

  if ! exec devcontainer exec \
    --workspace-folder "${repo_root}" \
    --config "${agent_devcontainer_config}" \
    --docker-path podman \
    bash --login; then
    open_troubleshooting_shell \
      "Agent container is not running. Start it with ./agent.sh"
  fi
}

show_proxy_log() {
  local -a since_arguments=()

  if [[ -n "${PROXY_LOG_SINCE:-}" ]]; then
    since_arguments=(--since "${PROXY_LOG_SINCE}")
  fi

  journalctl --user CONTAINER_NAME="${agent_proxy}" -o cat "${since_arguments[@]}" | awk '
    function quoted_host() {
      match($0, /"[^"]+"/)
      return substr($0, RSTART + 1, RLENGTH - 2)
    }
    /Established connection to host "/ { allowed[quoted_host()]++ }
    /refused on filtered domain "/      { refused[quoted_host()]++ }
    END {
      for (host in allowed) hosts[host] = 1
      for (host in refused) hosts[host] = 1
      for (host in hosts) {
        printf "%8d %8d %8d  %s\n", allowed[host] + refused[host], allowed[host], refused[host], host
      }
    }
  ' | sort -rn | {
    printf "%8s %8s %8s  %s\n" total allowed refused host
    cat
  }
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

  ensure_mount_points
  ensure_agent_network
  start_agent_proxy

  if ! devcontainer up "${up_arguments[@]}"; then
    open_troubleshooting_shell \
      "Failed to start agent container"
  fi

  if ! verify_agent_environment; then
    open_troubleshooting_shell \
      "Agent environment does not match expected containment"
  fi

  echo
  echo "Starting ${agent_tool} in ${repo_name}"
  echo

  local exit_code=0

  devcontainer exec \
    --workspace-folder "${repo_root}" \
    --config "${agent_devcontainer_config}" \
    --docker-path podman \
    "${agent_tool}" ||
    exit_code=$?

  if ((exit_code != 0)); then
    open_troubleshooting_shell \
      "${agent_tool} exited with code ${exit_code}"
  fi

  exit "${exit_code}"
}

agent_session_name() {
  printf '%s-agent-%s' "${repo_name}" "$1" | tr -c '[:alnum:]_-' '-'
}

start_tmux_session() {
  local session_name
  session_name="$(agent_session_name "${agent_tool}")"

  if [[ "${AGENT_SH_INSIDE_SESSION:-}" == "1" ]]; then
    enter_devcontainer
  fi

  # Rebuilding while agent is active would disrupt its agent session.
  if [[ "${mode}" == "rebuild" ]]; then
    local tool
    for tool in opencode claude; do
      if tmux has-session -t "=$(agent_session_name "${tool}")" 2>/dev/null; then
        printf 'Cannot rebuild while an agent session is active: %s\n' \
          "$(agent_session_name "${tool}")" >&2
        echo "Exit the active agent session before running ./agent.sh rebuild." >&2
        exit 1
      fi
    done
  fi

  if tmux has-session -t "=${session_name}" 2>/dev/null; then
    if [[ -n "${TMUX:-}" ]]; then
      exec tmux switch-client -t "=${session_name}"
    else
      exec tmux attach-session -t "=${session_name}"
    fi
  fi

  local session_command

  printf -v session_command \
    'AGENT_SH_INSIDE_SESSION=1 %q %q' \
    "${repo_root}/agent.sh" \
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

if [[ "${mode}" == "proxy-log" ]]; then
  show_proxy_log
  exit 0
fi

if ! verify_host_environment; then
  exit 1
fi

echo

if [[ "${mode}" == "shell" ]]; then
  open_existing_agent_shell
fi

start_tmux_session
