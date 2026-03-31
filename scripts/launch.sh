#!/usr/bin/env bash
# =============================================================================
# DevTools Container Launch Script — Linux / macOS
# Usage: chmod +x launch.sh && ./launch.sh
# =============================================================================

set -euo pipefail

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Platform detection ------------------------------------------------------
OS="$(uname -s)"
case "${OS}" in
    Linux*)  PLATFORM="linux"  ;;
    Darwin*) PLATFORM="macos"  ;;
    *)
        echo -e "${RED}Unsupported platform: ${OS}${NC}"
        exit 1
        ;;
esac

# --- Default values ----------------------------------------------------------
DEFAULT_IMAGE="purisev/devops-workspace:latest"
DEFAULT_SSH_DIR="${HOME}/.ssh"
DEFAULT_MEMORY=""   # no limit
DEFAULT_CPUS=""     # no limit

if [[ "${PLATFORM}" == "linux" ]]; then
    DEFAULT_WORKSPACES_DIR="/opt/workspaces"
else
    DEFAULT_WORKSPACES_DIR="${HOME}/workspaces"
fi

# --- Helpers -----------------------------------------------------------------

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║      DevTools Container Setup Script         ║${NC}"
    printf "${BOLD}${CYAN}║      Platform: %-30s║${NC}\n" "${PLATFORM}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""
}

read_input() {
    local prompt_text="$1"
    local default="${2:-}"
    local result

    if [[ -n "${default}" ]]; then
        echo -ne "  ${YELLOW}${prompt_text}${NC} ${DIM}[${default}]${NC}: "
    else
        echo -ne "  ${YELLOW}${prompt_text}${NC}: "
    fi
    read -r result
    echo "${result:-${default}}"
}

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
step() { echo -e "  ${CYAN}→${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $*"; }
err()  { echo -e "  ${RED}✗${NC} $*"; }
skip() { echo -e "  ${DIM}⊘ $* (already exists)${NC}"; }

create_dir() {
    local path="$1" label="$2"
    if [[ -d "${path}" ]]; then skip "${label}: ${path}"
    else mkdir -p "${path}" && ok "Created ${label}: ${path}"; fi
}

create_file() {
    local path="$1" label="$2" content="${3:-}"
    if [[ -f "${path}" ]]; then skip "${label}: ${path}"
    else printf '%s\n' "${content}" > "${path}" && ok "Created ${label}: ${path}"; fi
}

# --- Prerequisites -----------------------------------------------------------

if ! command -v docker &>/dev/null; then
    echo -e "${RED}Docker is not installed or not in PATH. Aborting.${NC}"
    exit 1
fi

# --- Input -------------------------------------------------------------------

print_header

echo -e "${BOLD}  Input${NC}"
echo -e "  ${DIM}────────────────────────────────────────────────${NC}"
echo ""

NAME=""
while [[ -z "${NAME}" ]]; do
    NAME="$(read_input "Container / user name")"
    [[ -z "${NAME}" ]] && err "Name cannot be empty."
done

if [[ ! "${NAME}" =~ ^[a-zA-Z0-9_.\-]+$ ]]; then
    err "Invalid name '${NAME}'. Use only letters, digits, hyphens, underscores, and dots."
    exit 1
fi

WORKSPACES_DIR="$(read_input "Workspaces base directory" "${DEFAULT_WORKSPACES_DIR}")"
SSH_DIR="$(read_input "SSH keys directory" "${DEFAULT_SSH_DIR}")"

# --- Image selection ---------------------------------------------------------

echo ""
echo -e "  ${BOLD}Docker image${NC}"
echo -e "  ${DIM}  1) Pull from Docker Hub  — ${DEFAULT_IMAGE}${NC}"
echo -e "  ${DIM}  2) Build locally now     — purisev/devops-workspace:local${NC}"
echo -e "  ${DIM}  3) Enter custom image name${NC}"
echo -ne "  ${YELLOW}Choice${NC} ${DIM}[1]${NC}: "
read -r _img_choice
_img_choice="${_img_choice:-1}"

case "${_img_choice}" in
    1)
        IMAGE="${DEFAULT_IMAGE}"
        ok "Using Docker Hub image: ${IMAGE}"
        ;;
    2)
        IMAGE="purisev/devops-workspace:local"
        echo ""
        step "Building image: ${IMAGE}"
        docker build -t "${IMAGE}" "$(dirname "$(dirname "$(realpath "$0")")")"
        ok "Build complete: ${IMAGE}"
        ;;
    3)
        IMAGE="$(read_input "Custom image name")"
        [[ -z "${IMAGE}" ]] && { err "Image name cannot be empty."; exit 1; }
        ok "Using custom image: ${IMAGE}"
        ;;
    *)
        err "Invalid choice '${_img_choice}'."
        exit 1
        ;;
esac
echo ""

MEMORY_LIMIT="$(read_input "Memory limit (e.g. 4g — leave empty for no limit)" "${DEFAULT_MEMORY}")"
CPU_LIMIT="$(read_input "CPU limit   (e.g. 2   — leave empty for no limit)" "${DEFAULT_CPUS}")"

# --- Derived paths -----------------------------------------------------------

CONTAINER_NAME="${NAME}"
SHARED_DIR="${WORKSPACES_DIR}/${NAME}"
USER_ROOTS_DIR="${WORKSPACES_DIR}/user-roots"
USER_DIR="${USER_ROOTS_DIR}/${NAME}"
ENV_FILE="${USER_DIR}/${NAME}.env"
GITCONFIG_FILE="${USER_DIR}/.gitconfig"
BASHRC_CUSTOM_FILE="${USER_DIR}/.bashrc_custom"
BASHRC_COMMON_FILE="${USER_ROOTS_DIR}/.bashrc_common"

# --- Warn if SSH dir missing -------------------------------------------------

if [[ ! -d "${SSH_DIR}" ]]; then
    echo ""
    warn "SSH directory not found: ${SSH_DIR}"
    echo -ne "  Continue anyway? [y/N]: "
    read -r _c
    [[ ! "${_c}" =~ ^[Yy]$ ]] && { err "Aborted."; exit 1; }
fi

# --- Create workspace structure ----------------------------------------------

echo ""
echo -e "${BOLD}  Creating workspace structure${NC}"
echo -e "  ${DIM}────────────────────────────────────────────────${NC}"

create_dir  "${SHARED_DIR}"  "Shared workspace"
create_dir  "${USER_DIR}"    "User config dir"

TODAY="$(date +%Y-%m-%d)"

create_file "${ENV_FILE}" "Environment file" \
"# Environment variables for container: ${NAME}
# Generated by launch.sh on ${TODAY}

TZ=UTC

# SSH password (optional — leave unset to use SSH key auth only):
# ROOT_PASSWORD=changeme
# DEVUSER_PASSWORD=changeme

# Add your custom variables below:"

create_file "${GITCONFIG_FILE}" ".gitconfig" \
"[user]
	name = Your Name
	email = your@email.com

[core]
	autocrlf = input
	editor = vim"

create_file "${BASHRC_CUSTOM_FILE}" ".bashrc_custom" \
"# Custom bash configuration for: ${NAME}
# Sourced automatically on container startup.

# Add your custom aliases, functions, and variables below:
# alias ll='ls -la'
# export MY_VAR=value"

create_file "${BASHRC_COMMON_FILE}" ".bashrc_common" \
"# Common bash configuration shared across all containers.
# Sourced automatically on container startup.

alias ll='ls -la'
alias la='ls -lah'
alias gs='git status'
alias gl='git log --oneline -10'"

# --- Generate devcontainer.json ----------------------------------------------

generate_devcontainer() {
    local dc_dir="${SHARED_DIR}/.devcontainer"
    local dc_file="${dc_dir}/devcontainer.json"

    mkdir -p "${dc_dir}"

    if [[ -f "${dc_file}" ]]; then
        skip "devcontainer.json: ${dc_file}"
        return
    fi

    # Build optional resource runArgs
    local resource_args=""
    [[ -n "${MEMORY_LIMIT}" ]] && resource_args+=",\n    \"--memory=${MEMORY_LIMIT}\""
    [[ -n "${CPU_LIMIT}" ]]    && resource_args+=",\n    \"--cpus=${CPU_LIMIT}\""

    # Note: ${localWorkspaceFolder} is a devcontainer variable — must not be expanded by bash.
    cat > "${dc_file}" << DEVCONTAINER
{
  "name": "${CONTAINER_NAME}",
  "image": "${IMAGE}",
  "runArgs": [
    "--privileged",
    "--hostname", "${CONTAINER_NAME}",
    "--env-file", "${ENV_FILE}"${resource_args}
  ],
  "workspaceMount": "source=\${localWorkspaceFolder},target=/opt/shared,type=bind",
  "workspaceFolder": "/opt/shared",
  "mounts": [
    "source=${NAME}-private,target=/opt/private,type=volume",
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
    "source=${SSH_DIR},target=/root/.ssh,type=bind,readonly",
    "source=${GITCONFIG_FILE},target=/root/.gitconfig,type=bind,readonly",
    "source=${BASHRC_COMMON_FILE},target=/root/.bashrc_common,type=bind,readonly",
    "source=${BASHRC_CUSTOM_FILE},target=/root/.bashrc_custom,type=bind"
  ],
  "remoteUser": "root",
  "shutdownAction": "none",
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-azuretools.vscode-docker",
        "ms-python.python",
        "hashicorp.terraform",
        "redhat.ansible",
        "ms-kubernetes-tools.vscode-kubernetes-tools",
        "redhat.vscode-yaml",
        "timonwong.shellcheck",
        "foxundermoon.shell-format"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash",
        "python.defaultInterpreterPath": "/workspace/.python-envs/toolset/bin/python",
        "dev.containers.dockerCredentialHelper": false
      }
    }
  }
}
DEVCONTAINER

    ok "Created devcontainer.json: ${dc_file}"
}

generate_devcontainer

# --- Summary -----------------------------------------------------------------

echo ""
echo -e "${BOLD}  Launch summary${NC}"
echo -e "  ${DIM}────────────────────────────────────────────────${NC}"
printf "  %-20s %s\n" "Container name:"  "${CYAN}${CONTAINER_NAME}${NC}"
printf "  %-20s %s\n" "Image:"           "${CYAN}${IMAGE}${NC}"
printf "  %-20s %s\n" "Workspaces dir:"  "${CYAN}${WORKSPACES_DIR}${NC}"
printf "  %-20s %s\n" "SSH directory:"   "${CYAN}${SSH_DIR}${NC}"
printf "  %-20s %s\n" "Shared dir:"      "${CYAN}${SHARED_DIR} → /opt/shared${NC}"
printf "  %-20s %s\n" "Memory limit:"    "${CYAN}${MEMORY_LIMIT:-unlimited}${NC}"
printf "  %-20s %s\n" "CPU limit:"       "${CYAN}${CPU_LIMIT:-unlimited}${NC}"
echo ""

# --- Handle existing container -----------------------------------------------

if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "${CONTAINER_NAME}"; then
    warn "Container '${CONTAINER_NAME}' already exists."
    echo -ne "  Remove and recreate it? [y/N]: "
    read -r _c
    if [[ "${_c}" =~ ^[Yy]$ ]]; then
        step "Removing existing container..."
        docker rm -f "${CONTAINER_NAME}" > /dev/null
        ok "Removed '${CONTAINER_NAME}'"
    else
        err "Aborted."
        exit 1
    fi
    echo ""
fi

# --- Confirm -----------------------------------------------------------------

echo -ne "  ${BOLD}Launch container now?${NC} [Y/n]: "
read -r _c

if [[ "${_c}" =~ ^[Nn]$ ]]; then
    echo ""
    warn "Container not started. Files are ready in ${USER_DIR}"
    echo -e "\n  ${DIM}Run manually when ready:${NC}\n"
    echo -e "${DIM}  docker run -d \\
    --name ${CONTAINER_NAME} \\
    --hostname ${CONTAINER_NAME} \\
    --restart always \\
    --privileged \\
    --env-file ${ENV_FILE} \\
    -v /var/run/docker.sock:/var/run/docker.sock \\
    -v ${SSH_DIR}:/root/.ssh:ro \\
    -v ${SHARED_DIR}:/opt/shared \\
    -v ${GITCONFIG_FILE}:/root/.gitconfig:ro \\
    -v ${BASHRC_COMMON_FILE}:/root/.bashrc_common:ro \\
    -v ${BASHRC_CUSTOM_FILE}:/root/.bashrc_custom \\
    ${IMAGE}${NC}"
    echo ""
    exit 0
fi

# --- Launch ------------------------------------------------------------------

echo ""
step "Launching container..."

# Build docker run args as an array to handle optional flags cleanly
DOCKER_ARGS=(
    run -d
    --name "${CONTAINER_NAME}"
    --hostname "${CONTAINER_NAME}"
    --restart always
    --privileged
    --env-file "${ENV_FILE}"
    --label "devtools.managed=true"
    --label "devtools.name=${NAME}"
    --label "devtools.workspaces_dir=${WORKSPACES_DIR}"
    --label "devtools.ssh_dir=${SSH_DIR}"
    --label "devtools.image=${IMAGE}"
    --label "devtools.memory=${MEMORY_LIMIT}"
    --label "devtools.cpus=${CPU_LIMIT}"
    --label "devtools.volume=${NAME}-private"
)
[[ -n "${MEMORY_LIMIT}" ]] && DOCKER_ARGS+=(--memory="${MEMORY_LIMIT}")
[[ -n "${CPU_LIMIT}" ]]    && DOCKER_ARGS+=(--cpus="${CPU_LIMIT}")
DOCKER_ARGS+=(
    -v "${NAME}-private:/opt/private"
    -v /var/run/docker.sock:/var/run/docker.sock
    -v "${SSH_DIR}:/root/.ssh:ro"
    -v "${SHARED_DIR}:/opt/shared"
    -v "${GITCONFIG_FILE}:/root/.gitconfig:ro"
    -v "${BASHRC_COMMON_FILE}:/root/.bashrc_common:ro"
    -v "${BASHRC_CUSTOM_FILE}:/root/.bashrc_custom"
    "${IMAGE}"
)

docker "${DOCKER_ARGS[@]}"

echo ""
ok "Container '${CONTAINER_NAME}' started successfully!"
echo ""
echo -e "  ${DIM}Useful commands:${NC}"
echo -e "  ${DIM}  ./manage.sh exec ${NAME}        — open shell${NC}"
echo -e "  ${DIM}  ./manage.sh status ${NAME}      — show status${NC}"
echo -e "  ${DIM}  ./manage.sh update ${NAME}      — update to latest image${NC}"
echo -e "  ${DIM}  ./manage.sh list               — list all containers${NC}"
echo ""
