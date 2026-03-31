#Requires -Version 5.1
# =============================================================================
# DevTools Container Launch Script — Windows (PowerShell)
# Usage: Right-click → "Run with PowerShell", or: .\launch.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

# --- Helpers -----------------------------------------------------------------

function Write-Header {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║      DevTools Container Setup Script         ║" -ForegroundColor Cyan
    Write-Host "║      Platform: Windows                       ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Read-Input {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default = ""
    )
    if ($Default) {
        $result = Read-Host "  $Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($result)) { return $Default }
        return $result.Trim()
    }
    $result = Read-Host "  $Prompt"
    return $result.Trim()
}

function Write-Ok   { Write-Host "  [OK]  $args" -ForegroundColor Green }
function Write-Step { Write-Host "  [ ->] $args" -ForegroundColor Cyan }
function Write-Warn { Write-Host "  [ !]  $args" -ForegroundColor Yellow }
function Write-Err  { Write-Host "  [ERR] $args" -ForegroundColor Red }
function Write-Skip { Write-Host "  [ --] $args (already exists)" -ForegroundColor DarkGray }

function New-DirIfMissing {
    param([string]$Path, [string]$Label)
    if (Test-Path -Path $Path -PathType Container) { Write-Skip "$Label`: $Path" }
    else {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Ok "Created $Label`: $Path"
    }
}

function New-FileIfMissing {
    param([string]$Path, [string]$Label, [string]$Content = "")
    if (Test-Path -Path $Path -PathType Leaf) { Write-Skip "$Label`: $Path" }
    else {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
        Write-Ok "Created $Label`: $Path"
    }
}

# Convert Windows path to Docker-compatible format (forward slashes).
# C:\Tools\workspaces → C:/Tools/workspaces
function ConvertTo-DockerPath {
    param([string]$Path)
    return $Path -replace '\\', '/'
}

# --- Prerequisites -----------------------------------------------------------

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker is not installed or not in PATH. Aborting." -ForegroundColor Red
    exit 1
}

# --- Input -------------------------------------------------------------------

Write-Header

$DefaultWorkspacesDir = "C:\Tools\workspaces"
$DefaultSshDir        = "$env:USERPROFILE\.ssh"
$DefaultImage         = "purisev/devops-workspace:latest"

Write-Host "  Input" -ForegroundColor White
Write-Host "  ────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

$Name = ""
while ([string]::IsNullOrWhiteSpace($Name)) {
    $Name = Read-Input -Prompt "Container / user name"
    if ([string]::IsNullOrWhiteSpace($Name)) { Write-Err "Name cannot be empty." }
}

if ($Name -notmatch '^[a-zA-Z0-9_.\-]+$') {
    Write-Err "Invalid name '$Name'. Use only letters, digits, hyphens, underscores, and dots."
    exit 1
}

$WorkspacesDir = Read-Input -Prompt "Workspaces base directory" -Default $DefaultWorkspacesDir
$SshDir        = Read-Input -Prompt "SSH keys directory"        -Default $DefaultSshDir

# --- Image selection ---------------------------------------------------------

Write-Host ""
Write-Host "  Docker image" -ForegroundColor White
Write-Host "    1) Pull from Docker Hub  — $DefaultImage"  -ForegroundColor DarkGray
Write-Host "    2) Build locally now     — purisev/devops-workspace:local" -ForegroundColor DarkGray
Write-Host "    3) Enter custom image name" -ForegroundColor DarkGray
$imgChoice = Read-Host "  Choice [1]"
if ([string]::IsNullOrWhiteSpace($imgChoice)) { $imgChoice = "1" }

switch ($imgChoice) {
    "1" {
        $Image = $DefaultImage
        Write-Ok "Using Docker Hub image: $Image"
    }
    "2" {
        $Image = "purisev/devops-workspace:local"
        Write-Host ""
        Write-Step "Building image: $Image"
        $ScriptRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
        docker build -t $Image $ScriptRoot
        if ($LASTEXITCODE -ne 0) { Write-Err "Build failed."; exit 1 }
        Write-Ok "Build complete: $Image"
    }
    "3" {
        $Image = Read-Host "  Custom image name"
        if ([string]::IsNullOrWhiteSpace($Image)) { Write-Err "Image name cannot be empty."; exit 1 }
        Write-Ok "Using custom image: $Image"
    }
    default {
        Write-Err "Invalid choice '$imgChoice'."
        exit 1
    }
}
Write-Host ""

$MemoryLimit   = Read-Input -Prompt "Memory limit (e.g. 4g — leave empty for no limit)" -Default ""
$CpuLimit      = Read-Input -Prompt "CPU limit   (e.g. 2   — leave empty for no limit)" -Default ""

# --- Derived paths -----------------------------------------------------------

$ContainerName    = $Name
$SharedDir        = Join-Path $WorkspacesDir $Name
$UserRootsDir     = Join-Path $WorkspacesDir "user-roots"
$UserDir          = Join-Path $UserRootsDir  $Name
$EnvFile          = Join-Path $UserDir       "$Name.env"
$GitconfigFile    = Join-Path $UserDir       ".gitconfig"
$BashrcCustomFile = Join-Path $UserDir       ".bashrc_custom"
$BashrcCommonFile = Join-Path $UserRootsDir  ".bashrc_common"

# Docker-compatible paths (forward slashes)
$DSharedDir        = ConvertTo-DockerPath $SharedDir
$DSshDir           = ConvertTo-DockerPath $SshDir
$DEnvFile          = ConvertTo-DockerPath $EnvFile
$DGitconfigFile    = ConvertTo-DockerPath $GitconfigFile
$DBashrcCustomFile = ConvertTo-DockerPath $BashrcCustomFile
$DBashrcCommonFile = ConvertTo-DockerPath $BashrcCommonFile

# --- Warn if SSH dir missing -------------------------------------------------

if (-not (Test-Path -Path $SshDir -PathType Container)) {
    Write-Host ""
    Write-Warn "SSH directory not found: $SshDir"
    $confirm = Read-Host "  Continue anyway? [y/N]"
    if ($confirm -notmatch '^[Yy]$') { Write-Err "Aborted."; exit 1 }
}

# --- Create workspace structure ----------------------------------------------

Write-Host ""
Write-Host "  Creating workspace structure" -ForegroundColor White
Write-Host "  ────────────────────────────────────────────────" -ForegroundColor DarkGray

New-DirIfMissing -Path $SharedDir -Label "Shared workspace"
New-DirIfMissing -Path $UserDir   -Label "User config dir"

$Today = Get-Date -Format "yyyy-MM-dd"

New-FileIfMissing -Path $EnvFile -Label "Environment file" -Content @"
# Environment variables for container: $Name
# Generated by launch.ps1 on $Today

TZ=UTC

# SSH password (optional - leave unset to use SSH key auth only):
# ROOT_PASSWORD=changeme
# DEVUSER_PASSWORD=changeme

# Add your custom variables below:
"@

New-FileIfMissing -Path $GitconfigFile -Label ".gitconfig" -Content @"
[user]
	name = Your Name
	email = your@email.com

[core]
	autocrlf = input
	editor = vim
"@

New-FileIfMissing -Path $BashrcCustomFile -Label ".bashrc_custom" -Content @"
# Custom bash configuration for: $Name
# Sourced automatically on container startup.

# Add your custom aliases, functions, and variables below:
# alias ll='ls -la'
# export MY_VAR=value
"@

New-FileIfMissing -Path $BashrcCommonFile -Label ".bashrc_common" -Content @"
# Common bash configuration shared across all containers.
# Sourced automatically on container startup.

alias ll='ls -la'
alias la='ls -lah'
alias gs='git status'
alias gl='git log --oneline -10'
"@

# --- Generate devcontainer.json ----------------------------------------------

$DcDir  = Join-Path $SharedDir ".devcontainer"
$DcFile = Join-Path $DcDir "devcontainer.json"

New-DirIfMissing -Path $DcDir -Label ".devcontainer dir"

if (Test-Path -Path $DcFile -PathType Leaf) {
    Write-Skip "devcontainer.json`: $DcFile"
} else {
    $resourceArgs = ""
    if ($MemoryLimit) { $resourceArgs += ",`n    `"--memory=$MemoryLimit`"" }
    if ($CpuLimit)    { $resourceArgs += ",`n    `"--cpus=$CpuLimit`"" }

    # Note: `${localWorkspaceFolder} is a devcontainer variable, not a PS variable.
    $dcContent = @"
{
  "name": "$ContainerName",
  "image": "$Image",
  "runArgs": [
    "--privileged",
    "--hostname", "$ContainerName",
    "--env-file", "$DEnvFile"$resourceArgs
  ],
  "workspaceMount": "source=`${localWorkspaceFolder},target=/opt/shared,type=bind",
  "workspaceFolder": "/opt/shared",
  "mounts": [
    "source=$Name-private,target=/opt/private,type=volume",
    "source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
    "source=$DSshDir,target=/root/.ssh,type=bind,readonly",
    "source=$DGitconfigFile,target=/root/.gitconfig,type=bind,readonly",
    "source=$DBashrcCommonFile,target=/root/.bashrc_common,type=bind,readonly",
    "source=$DBashrcCustomFile,target=/root/.bashrc_custom,type=bind"
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
"@
    [System.IO.File]::WriteAllText($DcFile, $dcContent, [System.Text.Encoding]::UTF8)
    Write-Ok "Created devcontainer.json`: $DcFile"
}

# --- Summary -----------------------------------------------------------------

Write-Host ""
Write-Host "  Launch summary" -ForegroundColor White
Write-Host "  ────────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Container name : " -NoNewline; Write-Host $ContainerName           -ForegroundColor Cyan
Write-Host "  Image          : " -NoNewline; Write-Host $Image                   -ForegroundColor Cyan
Write-Host "  Workspaces dir : " -NoNewline; Write-Host $WorkspacesDir           -ForegroundColor Cyan
Write-Host "  SSH directory  : " -NoNewline; Write-Host $SshDir                  -ForegroundColor Cyan
Write-Host "  Shared dir     : " -NoNewline; Write-Host "$SharedDir → /opt/shared" -ForegroundColor Cyan
Write-Host "  Memory limit   : " -NoNewline; Write-Host $(if ($MemoryLimit) { $MemoryLimit } else { "unlimited" }) -ForegroundColor Cyan
Write-Host "  CPU limit      : " -NoNewline; Write-Host $(if ($CpuLimit)    { $CpuLimit    } else { "unlimited" }) -ForegroundColor Cyan
Write-Host ""

# --- Handle existing container -----------------------------------------------

$existingNames = docker ps -a --format "{{.Names}}" 2>$null
if ($existingNames -contains $ContainerName) {
    Write-Warn "Container '$ContainerName' already exists."
    $confirm = Read-Host "  Remove and recreate it? [y/N]"
    if ($confirm -match '^[Yy]$') {
        Write-Step "Removing existing container..."
        docker rm -f $ContainerName | Out-Null
        Write-Ok "Removed '$ContainerName'"
    } else {
        Write-Err "Aborted."
        exit 1
    }
    Write-Host ""
}

# --- Confirm -----------------------------------------------------------------

$confirm = Read-Host "  Launch container now? [Y/n]"

if ($confirm -match '^[Nn]$') {
    Write-Host ""
    Write-Warn "Container not started. Files are ready in $UserDir"
    Write-Host ""
    Write-Host "  Run manually when ready:" -ForegroundColor DarkGray
    Write-Host "  docker run -d ``"                                                        -ForegroundColor DarkGray
    Write-Host "    --name $ContainerName ``"                                              -ForegroundColor DarkGray
    Write-Host "    --hostname $ContainerName ``"                                          -ForegroundColor DarkGray
    Write-Host "    --restart always --privileged ``"                                      -ForegroundColor DarkGray
    Write-Host "    --env-file $DEnvFile ``"                                               -ForegroundColor DarkGray
    Write-Host "    -v /var/run/docker.sock:/var/run/docker.sock ``"                       -ForegroundColor DarkGray
    Write-Host "    -v ${DSshDir}:/root/.ssh:ro ``"                                        -ForegroundColor DarkGray
    Write-Host "    -v ${DSharedDir}:/opt/shared ``"                                       -ForegroundColor DarkGray
    Write-Host "    -v ${DGitconfigFile}:/root/.gitconfig:ro ``"                           -ForegroundColor DarkGray
    Write-Host "    -v ${DBashrcCommonFile}:/root/.bashrc_common:ro ``"                    -ForegroundColor DarkGray
    Write-Host "    -v ${DBashrcCustomFile}:/root/.bashrc_custom ``"                    -ForegroundColor DarkGray
    Write-Host "    $Image"                                                                -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# --- Launch ------------------------------------------------------------------

Write-Host ""
Write-Step "Launching container..."

# Build docker run args as a list to handle optional flags cleanly
$RunArgs = @(
    "run", "-d",
    "--name", $ContainerName,
    "--hostname", $ContainerName,
    "--restart", "always",
    "--privileged",
    "--env-file", $DEnvFile,
    "--label", "devtools.managed=true",
    "--label", "devtools.name=$Name",
    "--label", "devtools.workspaces_dir=$WorkspacesDir",
    "--label", "devtools.ssh_dir=$SshDir",
    "--label", "devtools.image=$Image",
    "--label", "devtools.memory=$MemoryLimit",
    "--label", "devtools.cpus=$CpuLimit",
    "--label", "devtools.volume=$Name-private"
)
if ($MemoryLimit) { $RunArgs += @("--memory=$MemoryLimit") }
if ($CpuLimit)    { $RunArgs += @("--cpus=$CpuLimit") }
$RunArgs += @(
    "-v", "$Name-private:/opt/private",
    "-v", "/var/run/docker.sock:/var/run/docker.sock",
    "-v", "${DSshDir}:/root/.ssh:ro",
    "-v", "${DSharedDir}:/opt/shared",
    "-v", "${DGitconfigFile}:/root/.gitconfig:ro",
    "-v", "${DBashrcCommonFile}:/root/.bashrc_common:ro",
    "-v", "${DBashrcCustomFile}:/root/.bashrc_custom",
    $Image
)

docker @RunArgs | Out-Null

Write-Host ""
Write-Ok "Container '$ContainerName' started successfully!"
Write-Host ""
Write-Host "  Useful commands:" -ForegroundColor DarkGray
Write-Host "    .\manage.ps1 exec $Name        — open shell"   -ForegroundColor DarkGray
Write-Host "    .\manage.ps1 status $Name      — show status"  -ForegroundColor DarkGray
Write-Host "    .\manage.ps1 update $Name      — update image" -ForegroundColor DarkGray
Write-Host "    .\manage.ps1 list              — list all"     -ForegroundColor DarkGray
Write-Host ""
