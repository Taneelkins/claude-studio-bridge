#requires -Version 5
<#
  Claude Studio Bridge - Windows installer.

  From the cloned repo, in PowerShell:
      powershell -ExecutionPolicy Bypass -File scripts\install.ps1

  Does everything: builds the bridge, installs the plugin into the Roblox
  Plugins folder, registers the MCP server in %USERPROFILE%\.claude.json, and
  sets up the always-on daemon as a Scheduled Task (starts at logon, restarts
  on crash) so the Studio connection stays up across chats.

  Prereqs: Node.js on PATH (https://nodejs.org). No Rojo needed (the plugin is
  shipped prebuilt in release\ClaudeBridge.rbxm).
#>
$ErrorActionPreference = "Stop"

$Root   = Split-Path -Parent $PSScriptRoot
$Bridge = Join-Path $Root "bridge"
$Entry  = Join-Path $Bridge "dist\index.js"
$Daemon = Join-Path $Bridge "dist\daemon.js"

# --- Node ---
$NodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $NodeCmd) { throw "Node.js not found on PATH. Install from https://nodejs.org and re-run." }
$Node = $NodeCmd.Source
Write-Host "node: $Node"

# --- Build the bridge ---
Write-Host "Building bridge (npm install + build)..."
Push-Location $Bridge
try { npm install; npm run build } finally { Pop-Location }
if (-not (Test-Path $Entry)) { throw "Build failed: $Entry missing" }

# --- Install the plugin (prebuilt .rbxm, no Rojo) ---
$PluginsDir = Join-Path $env:LOCALAPPDATA "Roblox\Plugins"
New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null
$Rbxm = Join-Path $Root "release\ClaudeBridge.rbxm"
if (-not (Test-Path $Rbxm)) { throw "Prebuilt plugin missing: $Rbxm" }
Copy-Item $Rbxm (Join-Path $PluginsDir "ClaudeBridge.rbxm") -Force
Write-Host "Plugin installed -> $PluginsDir\ClaudeBridge.rbxm"

# --- Register the MCP server (safe JSON merge via Node) ---
& $Node (Join-Path $Root "scripts\register-mcp.mjs") $Entry
if ($LASTEXITCODE -ne 0) { throw "MCP registration failed" }

# --- Always-on daemon: try a Scheduled Task, fall back to a no-admin Startup launcher ---
$TaskName = "ClaudeBridgeDaemon"
try {
  $Action   = New-ScheduledTaskAction -Execute $Node -Argument "`"$Daemon`""
  $Trigger  = New-ScheduledTaskTrigger -AtLogOn
  $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 999
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
  Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings `
    -Description "Claude Studio Bridge daemon (always-on)" -ErrorAction Stop | Out-Null
  Start-ScheduledTask -TaskName $TaskName
  Write-Host "Daemon installed as Scheduled Task '$TaskName' and started."
} catch {
  Write-Host "Scheduled Task unavailable ($($_.Exception.Message))."
  Write-Host "Falling back to a no-admin Startup launcher..."
  $cmd     = '"' + $Node + '" "' + $Daemon + '"'
  $vbsLine = 'CreateObject("WScript.Shell").Run "' + ($cmd -replace '"', '""') + '", 0, False'
  $vbsPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeBridgeDaemon.vbs'
  Set-Content -LiteralPath $vbsPath -Value $vbsLine -Encoding ASCII
  Start-Process -FilePath $Node -ArgumentList ('"' + $Daemon + '"') -WindowStyle Hidden
  Write-Host "Daemon set to auto-start via $vbsPath, and started now."
}

Write-Host ""
Write-Host "Done. Next:"
Write-Host "  1. Restart Claude Code so it loads the roblox-studio tools."
Write-Host "  2. Open Roblox Studio - the Claude Bridge plugin auto-connects."
Write-Host ""
Write-Host "Verify the daemon:  Invoke-RestMethod http://127.0.0.1:44755/health"
Write-Host "Uninstall daemon:   Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false"
