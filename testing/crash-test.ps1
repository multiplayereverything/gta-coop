# Crash handling as players get it: CrashInfo.SA.asi present but switched off (CrashInfo.ini Enabled = 0), the game
# crashes on purpose -> it must close by itself (no window waiting for a click) and leave a log in CoopAndreas_crashes.
#   powershell -ExecutionPolicy Bypass -File testing\crash-test.ps1
param([int]$Port = 16788, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))
$ErrorActionPreference = 'Stop'
$AllowRealGame = $true   # this check may run on the real game on purpose (-GameDir), it only crashes the test it starts
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$dir = Join-Path $GameDir 'CoopAndreas\autotest\host'
function Events { $p = Join-Path $dir 'events.jsonl'; if (-not (Test-Path $p)) { return @() }; @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} }) }
function Cmd($line) { $path = Join-Path $dir 'commands.txt'; $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n"); for ($i = 0; $i -lt 100; $i++) { try { $fs = [IO.File]::Open($path, 'Append', 'Write', 'ReadWrite, Delete'); try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }; return } catch { Start-Sleep -Milliseconds 50 } } }
Get-ChildItem $dir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -Confirm:$false; New-Item -ItemType Directory -Force $dir | Out-Null
$crashDir = Join-Path $GameDir 'CoopAndreas_crashes'
$before = @(Get-ChildItem $crashDir -Filter *.log -ErrorAction SilentlyContinue).Count
$work = Join-Path $env:TEMP "coopandreas-crash-$Port"; New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden
$game = Start-Process (Join-Path $GameDir 'gta_sa.exe') -WorkingDirectory $GameDir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname host -autodir host"
try {
    $deadline = (Get-Date).AddSeconds(90); while (-not (Events | Where-Object { $_.ev -eq 'host_gained' }) -and (Get-Date) -lt $deadline) { Start-Sleep 1 }
    Start-Sleep 10
    Cmd 'crash'
    $closed = $game.WaitForExit(15000)
    $after = @(Get-ChildItem $crashDir -Filter *.log -ErrorAction SilentlyContinue).Count
    $log = Get-ChildItem $crashDir -Filter *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    Check 'A crash closes the game by itself (no crash window)' $closed $(if ($closed) { "exit code $($game.ExitCode)" } else { 'still open after 15 s: a window is waiting' })
    Check 'The crash is saved in CoopAndreas_crashes' ($after -gt $before) $(if ($log) { "$($log.Name): $((Get-Content $log.FullName -TotalCount 2)[1])" } else { 'no log' })
}
finally { if (-not $game.HasExited) { Stop-Process -Id $game.Id -Force }; if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
