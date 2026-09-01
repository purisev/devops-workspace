#!/usr/bin/env bash
# =============================================================================
# DevTools Container Management Script — Linux / macOS
# Usage: ./manage.sh <command> [name]
#
# Commands:
#   list              List all managed devtools containers
#   status  <name>    Show detailed status of a container
#   start   <name>    Start a stopped container
#   stop    <name>    Stop a running container
#   restart <name>    Restart a container
#   remove  <name>    Stop and remove a container (workspace files are kept)
#   update  <name>    Pull the latest image and recreate the container
#   logs    <name>    Follow container logs
#   exec    <name>    Open an interactive bash session
# =============================================================================

set -euo pipefail

# --- Colors ------------------------------------------------------------------
# Colours are enabled only when stdout is a real terminal and the user has not
# opted out (NO_COLOR, TERM=dumb). $'...' stores the *real* escape bytes, so a
# plain `echo` / `printf '%s'` renders them: no `echo -e`, no `%b`, and never a
# colour variable inside a printf format string.
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    NC=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' NC=''
fi

LABEL_FILTER="label=devtools.managed=true"

# --- Helpers -----------------------------------------------------------------

ok()   { echo "  ${GREEN}✓${NC} $*"; }
step() { echo "  ${CYAN}→${NC} $*"; }
warn() { echo "  ${YELLOW}⚠${NC} $*"; }
err()  { echo "  ${RED}✗${NC} $*" >&2; }

require_name() {
    if [[ -z "${1:-}" ]]; then
        err "Container name required. Usage: manage.sh ${COMMAND} <name>"
        exit 1
    fi
}

require_container() {
    local name="$1"
    local container="${name}"
    if ! docker inspect "${container}" &>/dev/null; then
        err "Container '${container}' not found."
        echo "  ${DIM}Run 'manage.sh list' to see all containers.${NC}"
        exit 1
    fi
}

label() {
    local container="$1"
    local key="$2"
    docker inspect --format "{{index .Config.Labels \"${key}\"}}" "${container}" 2>/dev/null
}

status_color() {
    case "$1" in
        running)   echo "${GREEN}$1${NC}" ;;
        exited)    echo "${RED}$1${NC}" ;;
        paused)    echo "${YELLOW}$1${NC}" ;;
        *)         echo "${DIM}$1${NC}" ;;
    esac
}

# --- Commands ----------------------------------------------------------------

cmd_list() {
    echo ""
    echo "${BOLD}  DevTools Containers${NC}"
    echo "  ${DIM}────────────────────────────────────────────────────────────────${NC}"

    local containers
    containers=$(docker ps -a --filter "${LABEL_FILTER}" --format "{{.Names}}" 2>/dev/null)

    if [[ -z "${containers}" ]]; then
        echo "  ${DIM}No managed devtools containers found.${NC}"
        echo "  ${DIM}Use launch.sh to create one.${NC}"
        echo ""
        return
    fi

    printf '  %s%-22s %-12s %-34s %-12s%s\n' "${BOLD}" "CONTAINER" "STATUS" "IMAGE" "CREATED" "${NC}"
    printf '  %s%s %s %s %s%s\n' "${DIM}" "──────────────────────" "────────────" "──────────────────────────────────" "────────────" "${NC}"

    while IFS= read -r container; do
        local raw_status image created
        raw_status=$(docker inspect --format '{{.State.Status}}' "${container}" 2>/dev/null || echo "unknown")
        image=$(label "${container}" "devtools.image")
        created=$(docker inspect --format '{{.Created}}' "${container}" 2>/dev/null | cut -c1-10)

        printf "  %-22s " "${container}"
        case "${raw_status}" in
            running) printf '%s%-12s%s' "${GREEN}" "${raw_status}" "${NC}" ;;
            exited)  printf '%s%-12s%s' "${RED}"   "${raw_status}" "${NC}" ;;
            *)       printf '%s%-12s%s' "${DIM}"   "${raw_status}" "${NC}" ;;
        esac
        printf '%-34s %s\n' "${image}" "${created}"
    done <<< "${containers}"

    echo ""
}

cmd_status() {
    local name="$1"
    local container="${name}"
    require_container "${name}"

    local raw_status image memory cpus workspaces_dir ssh_dir volume created
    raw_status=$(docker inspect --format '{{.State.Status}}' "${container}")
    image=$(label "${container}" "devtools.image")
    memory=$(label "${container}" "devtools.memory")
    cpus=$(label "${container}" "devtools.cpus")
    workspaces_dir=$(label "${container}" "devtools.workspaces_dir")
    ssh_dir=$(label "${container}" "devtools.ssh_dir")
    volume=$(label "${container}" "devtools.volume")
    created=$(docker inspect --format '{{.Created}}' "${container}" | cut -c1-19 | tr 'T' ' ')

    echo ""
    echo "${BOLD}  Container: ${CYAN}${container}${NC}"
    echo "  ${DIM}────────────────────────────────────────────────${NC}"
    printf "  %-18s %s\n" "Status:"         "$(status_color "${raw_status}")"
    printf "  %-18s %s\n" "Image:"          "${image}"
    printf "  %-18s %s\n" "Created:"        "${created}"
    printf "  %-18s %s\n" "Workspaces dir:" "${workspaces_dir}"
    printf "  %-18s %s\n" "SSH dir:"        "${ssh_dir}"
    printf "  %-18s %s\n" "Data volume:"    "${volume:-none} (/opt/private)"
    printf "  %-18s %s\n" "Memory limit:"   "${memory:-unlimited}"
    printf "  %-18s %s\n" "CPU limit:"      "${cpus:-unlimited}"

    if [[ "${raw_status}" == "running" ]]; then
        echo ""
        echo "  ${DIM}Resource usage:${NC}"
        docker stats --no-stream --format "  CPU: {{.CPUPerc}}   MEM: {{.MemUsage}}" "${container}" 2>/dev/null || true
    fi
    echo ""
}

cmd_start() {
    local name="$1"
    local container="${name}"
    require_container "${name}"
    step "Starting '${container}'..."
    docker start "${container}" > /dev/null
    ok "Started '${container}'"
}

cmd_stop() {
    local name="$1"
    local container="${name}"
    require_container "${name}"
    step "Stopping '${container}'..."
    docker stop "${container}" > /dev/null
    ok "Stopped '${container}'"
}

cmd_restart() {
    local name="$1"
    local container="${name}"
    require_container "${name}"
    step "Restarting '${container}'..."
    docker restart "${container}" > /dev/null
    ok "Restarted '${container}'"
}

cmd_remove() {
    local name="$1"
    local container="${name}"
    require_container "${name}"

    warn "This will remove container '${container}'. Workspace files are kept."
    printf '%s' "  Confirm? [y/N]: "
    read -r confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "  ${DIM}Aborted.${NC}"
        return
    fi

    local volume
    volume=$(label "${container}" "devtools.volume")

    step "Removing '${container}'..."
    docker rm -f "${container}" > /dev/null
    ok "Removed container '${container}'"

    if [[ -n "${volume}" ]] && docker volume inspect "${volume}" &>/dev/null; then
        printf '%s' "  Also remove data volume '${volume}'? [y/N]: "
        read -r _cv
        if [[ "${_cv}" =~ ^[Yy]$ ]]; then
            docker volume rm "${volume}" > /dev/null
            ok "Removed volume '${volume}'"
        else
            warn "Volume '${volume}' kept. Remove manually: docker volume rm ${volume}"
        fi
    fi
}

cmd_update() {
    local name="$1"
    local container="${name}"
    require_container "${name}"

    # Read stored config from container labels
    local image workspaces_dir ssh_dir memory_limit cpu_limit volume
    image=$(label "${container}" "devtools.image")
    workspaces_dir=$(label "${container}" "devtools.workspaces_dir")
    ssh_dir=$(label "${container}" "devtools.ssh_dir")
    memory_limit=$(label "${container}" "devtools.memory")
    cpu_limit=$(label "${container}" "devtools.cpus")
    volume=$(label "${container}" "devtools.volume")
    # Containers created before the volume label existed fall back to the
    # name launch.sh would have used.
    volume="${volume:-${name}-private}"

    # Re-derive paths
    local shared_dir user_dir env_file gitconfig bashrc_custom bashrc_common
    shared_dir="${workspaces_dir}/${name}"
    user_dir="${workspaces_dir}/user-roots/${name}"
    env_file="${user_dir}/${name}.env"
    gitconfig="${user_dir}/.gitconfig"
    bashrc_custom="${user_dir}/.bashrc_custom"
    bashrc_common="${workspaces_dir}/user-roots/.bashrc_common"

    echo ""
    step "Pulling latest image: ${image}..."
    docker pull "${image}"

    step "Removing old container '${container}'..."
    docker rm -f "${container}" > /dev/null

    step "Recreating container '${container}'..."

    local docker_args=(
        run -d
        --name "${container}"
        --hostname "${container}"
        --restart always
        --privileged
        --env-file "${env_file}"
        --label "devtools.managed=true"
        --label "devtools.name=${name}"
        --label "devtools.workspaces_dir=${workspaces_dir}"
        --label "devtools.ssh_dir=${ssh_dir}"
        --label "devtools.image=${image}"
        --label "devtools.memory=${memory_limit}"
        --label "devtools.cpus=${cpu_limit}"
        --label "devtools.volume=${volume}"
    )
    [[ -n "${memory_limit}" ]] && docker_args+=(--memory="${memory_limit}")
    [[ -n "${cpu_limit}" ]]    && docker_args+=(--cpus="${cpu_limit}")
    docker_args+=(
        -v "${volume}:/opt/private"
        -v /var/run/docker.sock:/var/run/docker.sock
        -v "${ssh_dir}:/root/.ssh:ro"
        -v "${shared_dir}:/opt/shared"
        -v "${gitconfig}:/root/.gitconfig:ro"
        -v "${bashrc_common}:/root/.bashrc_common:ro"
        -v "${bashrc_custom}:/root/.bashrc_custom"
        "${image}"
    )

    docker "${docker_args[@]}" > /dev/null
    echo ""
    ok "Container '${container}' updated and restarted."
}

cmd_logs() {
    local name="$1"
    local container="${name}"
    require_container "${name}"
    docker logs -f "${container}"
}

cmd_exec() {
    local name="$1"
    local container="${name}"
    require_container "${name}"
    step "Connecting to '${container}'..."
    docker exec -it "${container}" bash
}

# --- Usage -------------------------------------------------------------------

usage() {
    echo ""
    echo "${BOLD}Usage:${NC} manage.sh <command> [name]"
    echo ""
    echo "${BOLD}Commands:${NC}"
    echo "  ${CYAN}list${NC}              List all managed devtools containers"
    echo "  ${CYAN}status${NC}  <name>    Show detailed status and resource usage"
    echo "  ${CYAN}start${NC}   <name>    Start a stopped container"
    echo "  ${CYAN}stop${NC}    <name>    Stop a running container"
    echo "  ${CYAN}restart${NC} <name>    Restart a container"
    echo "  ${CYAN}remove${NC}  <name>    Remove a container (workspace files are kept)"
    echo "  ${CYAN}update${NC}  <name>    Pull the latest image and recreate the container"
    echo "  ${CYAN}logs${NC}    <name>    Follow container logs (Ctrl+C to exit)"
    echo "  ${CYAN}exec${NC}    <name>    Open an interactive bash session"
    echo ""
    echo "${BOLD}Examples:${NC}"
    echo "  manage.sh list"
    echo "  manage.sh status alice"
    echo "  manage.sh update alice"
    echo "  manage.sh exec alice"
    echo ""
}

# --- Dispatch ----------------------------------------------------------------

if ! command -v docker &>/dev/null; then
    err "Docker is not installed or not in PATH."
    exit 1
fi

COMMAND="${1:-list}"
NAME="${2:-}"

case "${COMMAND}" in
    list)                  cmd_list ;;
    status)   require_name "${NAME}"; cmd_status  "${NAME}" ;;
    start)    require_name "${NAME}"; cmd_start   "${NAME}" ;;
    stop)     require_name "${NAME}"; cmd_stop    "${NAME}" ;;
    restart)  require_name "${NAME}"; cmd_restart "${NAME}" ;;
    remove)   require_name "${NAME}"; cmd_remove  "${NAME}" ;;
    update)   require_name "${NAME}"; cmd_update  "${NAME}" ;;
    logs)     require_name "${NAME}"; cmd_logs    "${NAME}" ;;
    exec)     require_name "${NAME}"; cmd_exec    "${NAME}" ;;
    -h|--help|help) usage ;;
    *)
        err "Unknown command: '${COMMAND}'"
        usage
        exit 1
        ;;
esac
