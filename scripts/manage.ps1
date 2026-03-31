#Requires -Version 5.1
# =============================================================================
# DevTools Container Management Script — Windows (PowerShell)
# Usage: .\manage.ps1 <command> [name]
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

$ErrorActionPreference = "Stop"

$LabelFilter = "label=devtools.managed=true"

# --- Helpers -----------------------------------------------------------------

function Write-Ok   { Write-Host "  [OK]  $args" -ForegroundColor Green }
function Write-Step { Write-Host "  [ ->] $args" -ForegroundColor Cyan }
function Write-Warn { Write-Host "  [ !]  $args" -ForegroundColor Yellow }
function Write-Err  { Write-Host "  [ERR] $args" -ForegroundColor Red }

function Get-Label {
    param([string]$Container, [string]$Key)
    $result = docker inspect --format "{{index .Config.Labels `"$Key`"}}" $Container 2>$null
    return $result
}

function Get-ContainerStatus {
    param([string]$Container)
    return (docker inspect --format '{{.State.Status}}' $Container 2>$null)
}

function Assert-Name {
    param([string]$Name, [string]$Cmd)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Err "Container name required. Usage: manage.ps1 $Cmd <name>"
        exit 1
    }
}

function Assert-Container {
    param([string]$Name)
    $container = "${Name}-cli"
    $exists = docker inspect $container 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Container '$container' not found."
        Write-Host "  Run 'manage.ps1 list' to see all containers." -ForegroundColor DarkGray
        exit 1
    }
}

function ConvertTo-DockerPath {
    param([string]$Path)
    return $Path -replace '\\', '/'
}

# --- Commands ----------------------------------------------------------------

function Invoke-List {
    Write-Host ""
    Write-Host "  DevTools Containers" -ForegroundColor White
    Write-Host "  ────────────────────────────────────────────────────────────────" -ForegroundColor DarkGray

    $containers = docker ps -a --filter $LabelFilter --format "{{.Names}}" 2>$null

    if (-not $containers) {
        Write-Host "  No managed devtools containers found." -ForegroundColor DarkGray
        Write-Host "  Use launch.ps1 to create one." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    Write-Host ("  {0,-22} {1,-12} {2,-28} {3}" -f "CONTAINER", "STATUS", "IMAGE", "CREATED") -ForegroundColor White
    Write-Host ("  {0,-22} {1,-12} {2,-28} {3}" -f "──────────────────────", "───────────", "────────────────────────────", "───────────") -ForegroundColor DarkGray

    foreach ($container in $containers) {
        $status  = Get-ContainerStatus $container
        $image   = Get-Label $container "devtools.image"
        $created = (docker inspect --format '{{.Created}}' $container 2>$null).Substring(0, 10)

        $statusColor = switch ($status) {
            "running" { "Green" }
            "exited"  { "Red" }
            default   { "DarkGray" }
        }

        Write-Host ("  {0,-22} " -f $container) -NoNewline
        Write-Host ("{0,-12} " -f $status) -ForegroundColor $statusColor -NoNewline
        Write-Host ("{0,-28} {1}" -f $image, $created)
    }
    Write-Host ""
}

function Invoke-Status {
    param([string]$Name)
    $container = "${Name}-cli"
    Assert-Container $Name

    $status        = Get-ContainerStatus $container
    $image         = Get-Label $container "devtools.image"
    $memory        = Get-Label $container "devtools.memory"
    $cpus          = Get-Label $container "devtools.cpus"
    $workspacesDir = Get-Label $container "devtools.workspaces_dir"
    $sshDir        = Get-Label $container "devtools.ssh_dir"
    $volume        = Get-Label $container "devtools.volume"
    $created       = (docker inspect --format '{{.Created}}' $container 2>$null).Substring(0, 19).Replace('T', ' ')

    $statusColor = switch ($status) {
        "running" { "Green" }
        "exited"  { "Red" }
        default   { "Yellow" }
    }

    Write-Host ""
    Write-Host "  Container: " -NoNewline; Write-Host $container -ForegroundColor Cyan
    Write-Host "  ────────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ("  {0,-18} " -f "Status:")         -NoNewline; Write-Host $status -ForegroundColor $statusColor
    Write-Host ("  {0,-18} {1}" -f "Image:",          $image)
    Write-Host ("  {0,-18} {1}" -f "Created:",        $created)
    Write-Host ("  {0,-18} {1}" -f "Workspaces dir:", $workspacesDir)
    Write-Host ("  {0,-18} {1}" -f "SSH dir:",        $sshDir)
    Write-Host ("  {0,-18} {1}" -f "Data volume:",    $(if ($volume) { "$volume (/opt/private)" } else { "none" }))
    Write-Host ("  {0,-18} {1}" -f "Memory limit:",   $(if ($memory) { $memory } else { "unlimited" }))
    Write-Host ("  {0,-18} {1}" -f "CPU limit:",      $(if ($cpus)   { $cpus   } else { "unlimited" }))

    if ($status -eq "running") {
        Write-Host ""
        Write-Host "  Resource usage:" -ForegroundColor DarkGray
        docker stats --no-stream --format "  CPU: {{.CPUPerc}}   MEM: {{.MemUsage}}" $container 2>$null
    }
    Write-Host ""
}

function Invoke-Start {
    param([string]$Name)
    $container = "${Name}-cli"
    Assert-Container $Name
    Write-Step "Starting '$container'..."
    docker start $container | Out-Null
    Write-Ok "Started '$container'"
}

function Invoke-Stop {
    param([string]$Name)
    $container = "${Name}-cli"
    Assert-Container $Name
    Write-Step "Stopping '$container'..."
    docker stop $container | Out-Null
    Write-Ok "Stopped '$container'"
}

function Invoke-Restart {
    param([string]$Name)
    $container = "${Name}-cli"
    Assert-Container $Name
    Write-Step "Restarting '$container'..."
    docker restart $container | Out-Null
    Write-Ok "Restarted '$container'"
}

function Invoke-Remove {
    param([string]$Name)
    $container = "${Name}-cli"
    Assert-Container $Name

    Write-Warn "This will remove container '$container'. Workspace files are kept."
    $confirm = Read-Host "  Confirm? [y/N]"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "  Aborted." -ForegroundColor DarkGray
        return
    }

    $volume = Get-Label $container "devtools.volume"

    Write-Step "Removing '$container'..."
    docker rm -f $container | Out-Null
    Write-Ok "Removed container '$container'"

    if ($volume) {
        $volExists = docker volume inspect $volume 2>$null
        if ($LASTEXITCODE -eq 0) {
            $confirm = Read-Host "  Also remove data volume '$volume'? [y/N]"
            if ($confirm -match '^[Yy]$') {
                docker volume rm $volume | Out-Null
                Write-Ok "Removed volume '$volume'"
            } else {
                Write-Warn "Volume '$volume' kept. Remove manually: docker volume rm $volume"
            }
        }
    }
}

function Invoke-Update {
    param([string]$Name)
    $container = "${Name}-cli"
    Assert-Container $Name

    # Read stored config from container labels
    $image         = Get-Label $container "devtools.image"
    $workspacesDir = Get-Label $container "devtools.workspaces_dir"
    $sshDir        = Get-Label $container "devtools.ssh_dir"
    $memoryLimit   = Get-Label $container "devtools.memory"
    $cpuLimit      = Get-Label $container "devtools.cpus"
    $volume        = Get-Label $container "devtools.volume"

    # Re-derive paths
    $sharedDir      = Join-Path $workspacesDir $Name
    $userDir        = Join-Path $workspacesDir "user-roots\$Name"
    $envFile        = Join-Path $userDir "$Name.env"
    $gitconfig      = Join-Path $userDir ".gitconfig"
    $bashrcCustom   = Join-Path $userDir ".bashrc_custom"
    $bashrcCommon   = Join-Path $workspacesDir "user-roots\.bashrc_common"

    $dSharedDir     = ConvertTo-DockerPath $sharedDir
    $dSshDir        = ConvertTo-DockerPath $sshDir
    $dEnvFile       = ConvertTo-DockerPath $envFile
    $dGitconfig     = ConvertTo-DockerPath $gitconfig
    $dBashrcCustom  = ConvertTo-DockerPath $bashrcCustom
    $dBashrcCommon  = ConvertTo-DockerPath $bashrcCommon

    Write-Host ""
    Write-Step "Pulling latest image: $image..."
    docker pull $image

    Write-Step "Removing old container '$container'..."
    docker rm -f $container | Out-Null

    Write-Step "Recreating container '$container'..."

    $runArgs = @(
        "run", "-d",
        "--name", $container,
        "--hostname", $container,
        "--restart", "always",
        "--privileged",
        "--env-file", $dEnvFile,
        "--label", "devtools.managed=true",
        "--label", "devtools.name=$Name",
        "--label", "devtools.workspaces_dir=$workspacesDir",
        "--label", "devtools.ssh_dir=$sshDir",
        "--label", "devtools.image=$image",
        "--label", "devtools.memory=$memoryLimit",
        "--label", "devtools.cpus=$cpuLimit"
    )
    if ($memoryLimit) { $runArgs += @("--memory=$memoryLimit") }
    if ($cpuLimit)    { $runArgs += @("--cpus=$cpuLimit") }
    $runArgs += @(
        "-v", "$volume`:/opt/private",
        "-v", "/var/run/docker.sock:/var/run/docker.sock",
        "-v", "${dSshDir}:/root/.ssh:ro",
        "-v", "${dSharedDir}:/opt/shared",
        "-v", "${dGitconfig}:/root/.gitconfig:ro",
        "-v", "${dBashrcCommon}:/root/.bashrc_common:ro",
        "-v", "${dBashrcCustom}:/root/.bashrc_custom",
        $image
    )

    docker @runArgs | Out-Null
    Write-Host ""
    Write-Ok "Container '$container' updated and restarted."
}

function Invoke-Logs {
    param([string]$Name)
    $container = "${Name}-cli"
    Assert-Container $Name
    docker logs -f $container
}

function Invoke-Exec {
    param([string]$Name)
    $container = "${Name}-cli"
    Assert-Container $Name
    Write-Step "Connecting to '$container'..."
    docker exec -it $container bash
}

function Show-Usage {
    Write-Host ""
    Write-Host "Usage: manage.ps1 <command> [name]" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor White
    Write-Host "  list              List all managed devtools containers"
    Write-Host "  status  <name>    Show detailed status and resource usage"
    Write-Host "  start   <name>    Start a stopped container"
    Write-Host "  stop    <name>    Stop a running container"
    Write-Host "  restart <name>    Restart a container"
    Write-Host "  remove  <name>    Remove a container (workspace files are kept)"
    Write-Host "  update  <name>    Pull the latest image and recreate the container"
    Write-Host "  logs    <name>    Follow container logs (Ctrl+C to exit)"
    Write-Host "  exec    <name>    Open an interactive bash session"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  .\manage.ps1 list"
    Write-Host "  .\manage.ps1 status alice"
    Write-Host "  .\manage.ps1 update alice"
    Write-Host "  .\manage.ps1 exec alice"
    Write-Host ""
}

# --- Dispatch ----------------------------------------------------------------

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Err "Docker is not installed or not in PATH."
    exit 1
}

$Command = if ($args.Count -ge 1) { $args[0] } else { "list" }
$Name    = if ($args.Count -ge 2) { $args[1] } else { "" }

switch ($Command) {
    "list"    { Invoke-List }
    "status"  { Assert-Name $Name $Command; Invoke-Status  $Name }
    "start"   { Assert-Name $Name $Command; Invoke-Start   $Name }
    "stop"    { Assert-Name $Name $Command; Invoke-Stop    $Name }
    "restart" { Assert-Name $Name $Command; Invoke-Restart $Name }
    "remove"  { Assert-Name $Name $Command; Invoke-Remove  $Name }
    "update"  { Assert-Name $Name $Command; Invoke-Update  $Name }
    "logs"    { Assert-Name $Name $Command; Invoke-Logs    $Name }
    "exec"    { Assert-Name $Name $Command; Invoke-Exec    $Name }
    { $_ -in "-h","--help","help" } { Show-Usage }
    default {
        Write-Err "Unknown command: '$Command'"
        Show-Usage
        exit 1
    }
}
