# DevTools Workspace

A containerized development environment with a comprehensive toolset, per-user isolation, and lifecycle management scripts for Windows, Linux, and macOS.

## Features

- **All-in-one image** — Python, Ansible, Terraform, Vault, kubectl, Helm, Docker, AWS CLI, k9s, and more
- **Per-user isolation** — each user gets their own container, workspace, and configuration
- **Persistent private storage** — `/opt/private` backed by a named Docker volume (no host filesystem overhead)
- **Multi-arch** — native builds for `linux/amd64` and `linux/arm64` (Apple Silicon, AWS Graviton)
- **VS Code Dev Containers** — auto-generated `devcontainer.json` per workspace
- **Lifecycle management** — `manage` scripts for start / stop / restart / update / logs / exec

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows / macOS) or Docker Engine (Linux)
- PowerShell 5.1+ (Windows) or Bash (Linux / macOS)

## Quick Start

### 1. Get the image

**Option A — pull from Docker Hub (recommended):**
```bash
docker pull purisev/devops-workspace:latest
```
The launch scripts use this image by default — you can skip straight to step 2.

**Option B — build locally:**
```bash
docker build -t purisev/devops-workspace:local .
```
Multi-arch (requires Docker Buildx):
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t purisev/devops-workspace:local .
```
When the launch script asks for the image name, enter `purisev/devops-workspace:local`.

### 2. Launch a container

**Linux / macOS:**
```bash
chmod +x scripts/launch.sh scripts/manage.sh
./scripts/launch.sh
```

**Windows (PowerShell):**
```powershell
.\scripts\launch.ps1
```

The script will ask for:

| Prompt | Default (Linux) | Default (macOS) | Default (Windows) |
|---|---|---|---|
| Container / user name | — | — | — |
| Workspaces directory | `/opt/workspaces` | `~/workspaces` | `C:\Tools\workspaces` |
| SSH keys directory | `~/.ssh` | `~/.ssh` | `%USERPROFILE%\.ssh` |
| Docker image | `purisev/devops-workspace:latest` | same | same |
| Memory limit | *(none)* | same | same |
| CPU limit | *(none)* | same | same |

### 3. Connect

```bash
# Open a shell
./scripts/manage.sh exec <name>

# Or directly
docker exec -it <name> bash
```

## Workspace Structure

Each user gets the following layout on the host:

```
<workspaces_dir>/
├── <name>/                        # Shared workspace → /opt/shared
└── user-roots/
    ├── .bashrc_common             # Shared across all containers (read-only)
    └── <name>/
        ├── <name>.env             # Container environment variables
        ├── .gitconfig             # Git configuration (read-only)
        └── .bashrc_custom         # User shell customizations (editable from inside)
```

Inside the container:

| Path | Description |
|---|---|
| `/opt/shared` | Bind-mounted workspace directory |
| `/opt/private` | Persistent private storage (named Docker volume, survives updates) |
| `/root/.ssh` | SSH keys (read-only bind mount) |
| `/root/.bashrc_common` | Common shell config (read-only) |
| `/root/.bashrc_custom` | User shell config (writable from inside the container) |

## Managing Containers

**Linux / macOS:**

```bash
./scripts/manage.sh list                # List all devtools containers
./scripts/manage.sh status  <name>      # Status, mounts, resource usage
./scripts/manage.sh start   <name>      # Start a stopped container
./scripts/manage.sh stop    <name>      # Stop a running container
./scripts/manage.sh restart <name>      # Restart
./scripts/manage.sh update  <name>      # Pull latest image and recreate
./scripts/manage.sh logs    <name>      # Follow logs (Ctrl+C to exit)
./scripts/manage.sh exec    <name>      # Open interactive bash session
./scripts/manage.sh remove  <name>      # Remove container (keeps workspace files)
```

**Windows (PowerShell):**

```powershell
.\scripts\manage.ps1 list
.\scripts\manage.ps1 update <name>
.\scripts\manage.ps1 exec   <name>
# ... same commands
```

### Updating to a new image version

```bash
# Pull the latest published image
docker pull purisev/devops-workspace:latest

# Recreate the container — /opt/private data is preserved
./scripts/manage.sh update <name>
```

If you use a local build, rebuild first with `docker build -t purisev/devops-workspace:local .` and then run `manage update`.

## VS Code / Cursor Dev Containers

When you launch a container, the script automatically creates `.devcontainer/devcontainer.json` inside `<workspaces_dir>/<name>/`.

Open that folder in VS Code or Cursor and click **"Reopen in Container"** — the editor will connect to the running container and install the recommended extensions automatically:

- Docker
- Python
- Terraform (HashiCorp)
- Ansible (Red Hat)
- Kubernetes
- YAML
- ShellCheck
- shell-format

> `"shutdownAction": "none"` — the container keeps running when the editor window closes.

### Docker credentials inside the container

By default VS Code Dev Containers injects a credential helper into the container's `~/.docker/config.json` on every attach. This helper uses an IPC socket (`REMOTE_CONTAINERS_IPC`) that is only available inside VS Code's own terminal — **it does not work when you connect via SSH or `docker exec`**, which is the primary way to use this workspace.

The generated `devcontainer.json` disables this behavior:

```json
"settings": {
  "dev.containers.dockerCredentialHelper": false
}
```

With this setting VS Code will not modify the container's Docker config. To authenticate with private registries, run `docker login` inside the container directly — credentials are stored in `/root/.docker/config.json` inside the container and survive restarts (but not `manage update`, since that recreates the container). For credentials that must persist across updates, store them under `/opt/private/.docker/` and set `DOCKER_CONFIG=/opt/private/.docker` in your `.env` file.

## Environment Variables

Edit `<workspaces_dir>/user-roots/<name>/<name>.env` to configure the container:

```env
TZ=UTC

# Optional: enable SSH password login
# ROOT_PASSWORD=changeme
# DEVUSER_PASSWORD=changeme

# Add your own variables:
# VAULT_ADDR=https://vault.example.com
# AWS_PROFILE=default
```

> By default, root SSH login uses **key authentication only** (keys from the mounted `~/.ssh`). Password auth for root is disabled at the SSH level (`PermitRootLogin prohibit-password`) unless `ROOT_PASSWORD` is set.

## Customizing the Shell

`.bashrc_custom` is mounted **read-write** — you can edit it from inside the container and changes are immediately reflected on the host:

```bash
# Inside the container
echo "alias k='kubectl'" >> ~/.bashrc_custom
source ~/.bashrc_custom
```

`.bashrc_common` is read-only and shared across all users. Edit it on the host directly.

## Security Notes

| Concern | Mitigation |
|---|---|
| `--privileged` flag | Required for Docker-in-Docker; scope to trusted users only |
| Docker socket mount | Grants full Docker daemon access — equivalent to root on the host |
| SSH root login | Key-only by default (`PermitRootLogin prohibit-password`) |
| Sensitive mounts | `.gitconfig`, `.ssh`, `.bashrc_common` are mounted read-only |

## Multi-Architecture Support

The image builds natively for `linux/amd64` and `linux/arm64`.
CI uses QEMU emulation via `docker/setup-qemu-action` to cross-compile arm64 on amd64 runners.

To build locally for both platforms:

```bash
docker buildx create --use
docker buildx build --platform linux/amd64,linux/arm64 -t purisev/devops-workspace:local .
```

## Build Arguments

All version pins are defined at the top of the Dockerfile and can be overridden at build time:

```bash
docker build \
  --build-arg PYTHON_VERSION=3.13 \
  --build-arg TERRAFORM_VERSION=1.12.1 \
  --build-arg VAULT_VERSION=1.20.4 \
  --build-arg POSTGRESQL_CLIENT_VERSION=18 \
  -t purisev/devops-workspace:local .
```

## License

Copyright 2026 Iurii Purisev.
Licensed under the [Apache License, Version 2.0](LICENSE).
