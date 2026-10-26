# Boots one test game (no saving) and prints where it would keep its saves: must be its own autotest folder.
#   powershell -ExecutionPolicy Bypass -File testingboot-check.ps1
param([int]$Port = 16789, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$dir = Join-Path $GameDir 'CoopAndreas\autotest\host'
function Events { $p = Join-Path $dir 'events.jsonl'; if (-not (Test-Path $p)) { return @() }; @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} }) }
function Status { try { Get-Content (Join-Path $dir 'status.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null } }
function Cmd($line) { $path = Join-Path $dir 'commands.txt'; $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n"); for ($i = 0; $i -lt 100; $i++) { try { $fs = [IO.File]::Open($path, 'Append', 'Write', 'ReadWrite, Delete'); try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }; return } catch { Start-Sleep -Milliseconds 50 } } }
Get-ChildItem $dir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -Confirm:$false; New-Item -ItemType Directory -Force $dir | Out-Null
$work = Join-Path $env:TEMP "coopandreas-bootcheck-$Port"; New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden
$game = Start-Process (Join-Path $GameDir 'gta_sa.exe') -WorkingDirectory $GameDir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname host -autodir host"
try {
    $deadline = (Get-Date).AddSeconds(90); while (-not (Events | Where-Object { $_.ev -eq 'host_gained' }) -and (Get-Date) -lt $deadline) { Start-Sleep 1 }
    Start-Sleep 15
    $b = Events | Where-Object { $_.ev -eq "boot" } | Select-Object -First 1; $s = Status
    Write-Host "    userDir=$($s.userDir)"; Write-Host "    savePrefix=$($s.savePrefix)"; Write-Host "    events: $((Events | Select-Object -Last 3 | ConvertTo-Json -Compress))"
}
finally { if (-not $game.HasExited) { Stop-Process -Id $game.Id -Force }; if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
