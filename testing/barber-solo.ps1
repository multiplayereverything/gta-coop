# One game on the test copy: walk into the Idlewood barber, stand on the chair spot, and check the haircut starts
# (minigame flag). Used to check the shop-chair rule (Coop 1D21) without a partner.
#   powershell -ExecutionPolicy Bypass -File testing\barber-solo.ps1
param([int]$Port = 16799, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$dir = Join-Path $GameDir 'CoopAndreas\autotest\host'
function Events { $p = Join-Path $dir 'events.jsonl'; if (-not (Test-Path $p)) { return @() }; @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} }) }
function Status { try { Get-Content (Join-Path $dir 'status.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null } }
function Cmd($line) { $path = Join-Path $dir 'commands.txt'; $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n"); for ($i = 0; $i -lt 100; $i++) { try { $fs = [IO.File]::Open($path, 'Append', 'Write', 'ReadWrite, Delete'); try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }; return } catch { Start-Sleep -Milliseconds 50 } } }
Get-ChildItem $dir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -Confirm:$false; New-Item -ItemType Directory -Force $dir | Out-Null
$work = Join-Path $env:TEMP "coopandreas-barber-$Port"; New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden
$game = Start-Process (Join-Path $GameDir 'gta_sa.exe') -WorkingDirectory $GameDir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname host -autodir host"
try {
    $deadline = (Get-Date).AddSeconds(90); while (-not (Events | Where-Object { $_.ev -eq 'host_gained' }) -and (Get-Date) -lt $deadline) { Start-Sleep 1 }
    Start-Sleep 15
    Cmd 'enex BARBERS 1'; Cmd 'teleport 2073.0 -1795.5 13.6'; Start-Sleep 3
    $door = @((Status).doors) | Where-Object { $_.name -eq 'BARBERS' -and $_.z -lt 500 } | Select-Object -First 1
    Cmd ("teleport {0} {1} {2}" -f $door.x, $door.y, ($door.z + 0.6)); Start-Sleep 9
    Cmd 'countpeds 20 156 176 177'; Start-Sleep 1
    $s = Status; Write-Host "inside: area=$($s.area) pos=$($s.local.x),$($s.local.y),$($s.local.z) barber: $((Events | Where-Object { $_.cmd -like 'countpeds*' } | Select-Object -Last 1).result)"
    Cmd 'teleport 414.3 -19.9 1001.3'
    $deadline = (Get-Date).AddSeconds(15); while (-not (Status).minigame -and (Get-Date) -lt $deadline) { Start-Sleep 1 }
    $s = Status
    Check 'Alone on the barber chair spot: the haircut starts' ($s.minigame) "minigame=$($s.minigame) pos=$($s.local.x),$($s.local.y),$($s.local.z) dpc=$($s.pad.dpc) mission=$($s.onMission)"
}
finally { if (-not $game.HasExited) { Stop-Process -Id $game.Id -Force }; if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
