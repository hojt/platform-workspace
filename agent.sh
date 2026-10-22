#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_name="$(basename -- "${repo_root}")"
agent_devcontainer_config="${repo_root}/.devcontainer/agent/devcontainer.json"
agent_network="${repo_name}-agent"
agent_egress_network="${repo_name}-agent-egress"
agent_proxy="${repo_name}-agent-proxy"
agent_proxy_dir="${repo_root}/.devcontainer/agent/proxy"
agent_workspace_mode="mount"
claude_token_file="${XDG_CONFIG_HOME:-${HOME}/.config}/claude-agent/oauth-token"

baseline_protected_paths=(
  .
  .devcontainer
  .git
  AGENTS.md
  CLAUDE.md
  Taskfile.yml
  agent.sh
  dev.sh
  opencode.json
)

baseline_isolated_paths=(
  .opencode
  .claude
  /home/developer/.local/share/opencode
  /home/developer/.claude
)

# Defaults; .devcontainer/agent/sandbox.conf describes the actual layout.
workspace_repositories=()
agent_writable_paths=()
agent_protected_paths=()
agent_isolated_paths=()
agent_hidden_paths=()

agent_sandbox_config="${repo_root}/.devcontainer/agent/sandbox.conf"

if [[ -f "${agent_sandbox_config}" ]]; then
  # shellcheck source=.devcontainer/agent/sandbox.conf
  source "${agent_sandbox_config}"
fi

agent_workspace="/workspaces/${repo_name}"
if [[ "${agent_workspace_mode}" == "clone" ]]; then
  agent_workspace="/agent-workspaces/${repo_name}"
fi
agent_upstream="/upstream/${repo_name}.git"
agent_delivery="/agent-delivery/${repo_name}.git"

mode="${1:-dev}"
agent_tool="opencode"

green=""
red=""
yellow=""
reset=""

usage() {
  printf 'Usage: %s [rebuild|shell|fetch|proxy-log|claude]\n' "${0}"
  printf '  PROXY_LOG_SINCE=<time>  limit proxy-log (e.g. -1h, today)\n'
}

parse_arguments() {
  if (($# > 1)); then
    usage >&2
    exit 2
  fi

  case "${mode}" in
  dev | rebuild | shell | fetch | proxy-log)
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
  # stdout has a TTY, so ANSI colors are safe to use.
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

host_path() {
  local path="$1"

  if [[ "${path}" == repos/* ]]; then
    printf '%s/../%s' "${repo_root}" "${path#repos/}"
  else
    printf '%s/%s' "${repo_root}" "${path}"
  fi
}

agent_path() {
  local path="$1"

  if [[ "${path}" == /* ]]; then
    printf '%s' "${path}"
  else
    printf '%s/%s' "${agent_workspace}" "${path}"
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

  check_file \
    "${agent_sandbox_config}" \
    ".devcontainer/agent/sandbox.conf" ||
    status=1

  local repo
  for repo in "${workspace_repositories[@]}"; do
    check_host_repository \
      "${repo_root}/../${repo}" \
      "${repo} repository" ||
      status=1
  done

  if [[ "${agent_tool}" == "claude" ]]; then
    check_file \
      "${claude_token_file}" \
      "Claude Code token (create with: claude setup-token)" ||
      status=1
  fi

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

agent_checks=()

queue_check() {
  local kind="$1"
  local description="$2"
  shift 2

  local line arg
  printf -v line '%q %q' "${kind}" "${description}"
  for arg in "$@"; do
    printf -v line '%s %q' "${line}" "${arg}"
  done

  agent_checks+=("${line}")
}

check_agent() {
  queue_check check "$@"
}

warn_agent() {
  queue_check warn "$@"
}

check_agent_repository() { check_agent "$2" test -d "$1/.git"; }
# shellcheck disable=SC2016
check_agent_path_readonly() { check_agent "$2" sh -c '! test -w "$1"' _ "$1"; }
check_agent_path_writable() { check_agent "$2" test -w "$1"; }
# shellcheck disable=SC2016
check_agent_path_absent() { check_agent "$2" sh -c '! test -e "$1"' _ "$1"; }
# shellcheck disable=SC2016
check_agent_socket_absent() { check_agent "$2" sh -c '! test -S "$1"' _ "$1"; }
check_agent_mountpoint() { check_agent "$2" mountpoint -q "$1"; }
# shellcheck disable=SC2016
check_agent_env_absent() { check_agent "$2" sh -c '! printenv "$1"' _ "$1"; }
# shellcheck disable=SC2016
check_agent_command_absent() { check_agent "$2" sh -c '! command -v "$1"' _ "$1"; }
check_agent_cannot_escalate() { check_agent "$1" sh -c '! sudo -n true'; }

run_agent_checks() {
  local expected="${#agent_checks[@]}"
  local received=0
  local status=0
  local script results outcome description

  # shellcheck disable=SC2016
  script='
check() {
  d="$1"; shift
  if "$@" >/dev/null 2>&1; then printf "pass\t%s\n" "$d"; else printf "fail\t%s\n" "$d"; fi
}
warn() {
  d="$1"; shift
  if "$@" >/dev/null 2>&1; then printf "pass\t%s\n" "$d"; else printf "warn\t%s\n" "$d"; fi
}
'
  script+="$(printf '%s\n' "${agent_checks[@]}")"
  agent_checks=()

  results="$(agent_exec bash -c "${script}")" || true

  while IFS=$'\t' read -r outcome description; do
    [[ -z "${outcome}" ]] && continue
    received=$((received + 1))

    case "${outcome}" in
    pass) check_passed "${description}" ;;
    warn) printf '  %s!%s %s\n' "${yellow}" "${reset}" "${description}" >&2 ;;
    *) check_failed "${description}" || status=1 ;;
    esac
  done <<<"${results}"

  if ((received != expected)); then
    check_failed "all ${expected} checks reported, got ${received}" || true
    status=1
  fi

  return "${status}"
}

verify_agent_environment() {
  local status=0

  echo
  echo "Verifying agent environment"

  init_colors

  check_agent_repository \
    "${agent_workspace}" \
    "${repo_name} repository is available" ||
    status=1

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

  local repo
  for repo in "${workspace_repositories[@]}"; do
    check_agent_repository \
      "${agent_workspace}/repos/${repo}" \
      "${repo} repository is available" ||
      status=1
  done

  local path

  if [[ "${agent_workspace_mode}" == "clone" ]]; then
    check_agent_mountpoint "${agent_workspace}" "workspace is an agent-owned clone" ||
      status=1
    check_agent_path_writable "${agent_workspace}" "workspace is writable" ||
      status=1
    check_agent_path_readonly "${agent_upstream}" "upstream repository is read-only" ||
      status=1
    check_agent_path_absent "/workspaces/${repo_name}" "developer working tree is not mounted" ||
      status=1
    check_agent_mountpoint "${agent_delivery}" "delivery repository is isolated" ||
      status=1
    check_agent_path_writable "${agent_delivery}" "delivery repository is writable" ||
      status=1
  else
    for path in \
      "${baseline_protected_paths[@]}" \
      "${agent_protected_paths[@]}"; do
      check_agent_path_readonly "$(agent_path "${path}")" "${path} is read-only" ||
        status=1
    done

    for repo in "${workspace_repositories[@]}"; do
      for path in "repos/${repo}" "repos/${repo}/.git"; do
        check_agent_path_readonly "$(agent_path "${path}")" "${path} is read-only" ||
          status=1
      done
    done

    for path in "${agent_writable_paths[@]}"; do
      check_agent_path_writable "$(agent_path "${path}")" "${path} is writable" ||
        status=1
    done
  fi

  for path in \
    "${baseline_isolated_paths[@]}" \
    "${agent_isolated_paths[@]}" \
    "${agent_hidden_paths[@]}"; do
    check_agent_mountpoint "$(agent_path "${path}")" "${path} is isolated" ||
      status=1
  done

  for path in \
    "${baseline_isolated_paths[@]}" \
    "${agent_isolated_paths[@]}"; do
    check_agent_path_writable "$(agent_path "${path}")" "${path} is writable" ||
      status=1
  done

  for path in "${agent_hidden_paths[@]}"; do
    # shellcheck disable=SC2016
    check_agent "${path} is hidden" \
      sh -c '[ -z "$(ls -A "$1")" ]' _ "$(agent_path "${path}")" ||
      status=1
  done

  check_agent_command_absent podman "podman is not installed" || status=1
  check_agent_cannot_escalate "privilege escalation is not possible" || status=1

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
    sh -c '[ "$(ls -A "$(dirname "$1")")" = "$(basename "$1")" ]' _ "${agent_workspace}" ||
    status=1

  check_agent "Claude Code managed settings are in place" \
    test -f /etc/claude-code/managed-settings.json ||
    status=1

  run_agent_checks || status=1

  if ((status != 0)); then
    echo >&2
    echo "Agent environment verification failed." >&2
  fi

  return "${status}"
}

ensure_mount_points() {
  local repo path

  for repo in "${workspace_repositories[@]}"; do
    mkdir -p "${repo_root}/repos/${repo}"
  done

  for path in "${agent_hidden_paths[@]}"; do
    mkdir -p "$(host_path "${path}")"
  done
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

agent_container_id() {
  podman ps \
    --filter "label=homelab.agent-workspace=${repo_name}" \
    --format '{{.ID}}' |
    head -n 1
}

fetch_agent_branches() {
  if [[ "${agent_workspace_mode}" != "clone" ]]; then
    echo "fetch requires agent_workspace_mode=clone in sandbox.conf" >&2
    exit 1
  fi

  local bundle
  bundle="$(mktemp --suffix=.bundle)"
  # shellcheck disable=SC2064
  trap "rm -f '${bundle}'" RETURN

  local container_id
  container_id="$(agent_container_id)"

  if [[ -z "${container_id}" ]]; then
    echo "The agent container is not running. Start it from the host with ./agent.sh." >&2
    exit 1
  fi

  # The bundle is created inside the agent container and only read as data
  # here. Git never runs inside the delivery repository outside the agent
  # container.
  # shellcheck disable=SC2016
  if ! podman exec --user developer "${container_id}" sh -euc '
    cd "$1"
    if [ -n "$(git for-each-ref --format=x refs/heads/agent/)" ]; then
      git bundle create --quiet - --branches="agent/*" | base64
    fi
  ' _ "${agent_delivery}" | base64 --decode >"${bundle}"; then
    echo "Could not read agent branches from the agent container." >&2
    exit 1
  fi

  if [[ -s "${bundle}" ]]; then
    git -C "${repo_root}" fetch --prune --no-tags \
      "${bundle}" '+refs/heads/agent/*:refs/remotes/agent/*'
  else
    # No agent branches are delivered; drop any previously fetched ones.
    git -C "${repo_root}" for-each-ref \
      --format='delete %(refname)' refs/remotes/agent/ |
      git -C "${repo_root}" update-ref --stdin
  fi

  echo
  echo "Agent branches:"
  git -C "${repo_root}" for-each-ref refs/remotes/agent \
    --format='  %(refname:short)  %(committerdate:relative)  %(subject)'
}

prepare_agent_clone() {
  echo
  echo "Preparing agent clone of ${repo_name}"

  # shellcheck disable=SC2016
  agent_exec sh -euc '
    workspace="$1"
    upstream="$2"
    delivery="$3"
    repo="$4"
    cd "${workspace}"

    if [ ! -d .git ]; then
      git init --quiet
      git remote add origin "file://${upstream}"
    fi

    git fetch --quiet origin
    git remote set-head origin --auto >/dev/null

    default_branch="$(git symbolic-ref --short refs/remotes/origin/HEAD)"
    local_branch="${default_branch#origin/}"

    if ! git rev-parse --quiet --verify HEAD >/dev/null; then
      git checkout --quiet --force -B "${local_branch}" "${default_branch}"
    elif [ "$(git symbolic-ref --quiet --short HEAD)" = "${local_branch}" ] &&
      [ -z "$(git status --porcelain)" ]; then
      git merge --quiet --ff-only "${default_branch}" ||
        echo "Agent clone: ${local_branch} could not be fast-forwarded" >&2
    fi

    for readme in .opencode/README.md .claude/README.md; do
      if git ls-files --error-unmatch "${readme}" >/dev/null 2>&1; then
        git update-index --skip-worktree "${readme}"
      fi
    done

    if [ ! -f "${delivery}/HEAD" ]; then
      git init --bare --quiet "${delivery}"
    fi

    if ! git remote get-url delivery >/dev/null 2>&1; then
      git remote add delivery "file://${delivery}"
    fi

    git config remote.pushDefault delivery
    git config push.default current
    git config user.name "Coding agent"
    git config user.email "coding-agent@${repo}.invalid"
  ' _ "${agent_workspace}" "${agent_upstream}" "${agent_delivery}" "${repo_name}"
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

  if [[ "${agent_workspace_mode}" == "clone" ]] &&
    ! prepare_agent_clone; then
    open_troubleshooting_shell \
      "Failed to prepare agent clone"
  fi

  if ! verify_agent_environment; then
    open_troubleshooting_shell \
      "Agent environment does not match expected containment"
  fi

  echo
  echo "Starting ${agent_tool} in ${repo_name}"
  echo

  local -a exec_arguments=(
    --workspace-folder "${repo_root}"
    --config "${agent_devcontainer_config}"
    --docker-path podman
  )

  if [[ "${agent_tool}" == "claude" ]]; then
    local claude_token
    claude_token="$(<"${claude_token_file}")"
    exec_arguments+=(--remote-env "CLAUDE_CODE_OAUTH_TOKEN=${claude_token}")
  fi

  local exit_code=0

  devcontainer exec "${exec_arguments[@]}" "${agent_tool}" ||
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
  # Normalize the repository name for use as a tmux session name.
  local session_name
  session_name="$(agent_session_name "${agent_tool}")"

  # This branch executes inside the repository-specific tmux session.
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

in_container() {
  [[ -f /run/.containerenv ]]
}

parse_arguments "$@"

if in_container; then
  case "${mode}" in
  fetch)
    ;;
  *)
    printf './agent.sh %s runs on the host. From a container, only ./agent.sh fetch is available.\n' "${mode}" >&2
    exit 2
    ;;
  esac
fi

if [[ "${mode}" == "proxy-log" ]]; then
  show_proxy_log
  exit 0
fi

if [[ "${mode}" == "fetch" ]]; then
  fetch_agent_branches
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
