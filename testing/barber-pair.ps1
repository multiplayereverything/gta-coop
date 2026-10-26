# Barber chair with two players: only one gets seated (optionally after the partner died and respawned).
#   powershell -ExecutionPolicy Bypass -File testing\barber-pair.ps1 [-KillFirst] [-KillInMission]
param([int]$Port = 16798, [switch]$KillFirst, [switch]$KillInMission, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\barber-pair-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
New-Item -ItemType Directory -Force $report | Out-Null
$script:ReportDir = $report
$PartnerDir = "$GameDir (partner)"
function GameDirOf($who) { if ($who -eq 'partner') { $PartnerDir } else { $GameDir } }
function AutoDir($who) { Join-Path (GameDirOf $who) "CoopAndreas\autotest\$who" }
function Events($who) { $p = Join-Path (AutoDir $who) 'events.jsonl'; if (-not (Test-Path $p)) { return @() }; @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} }) }
function Status($who) { try { Get-Content (Join-Path (AutoDir $who) 'status.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null } }
function Cmd($who, $line) {
    $path = Join-Path (AutoDir $who) 'commands.txt'; $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n")
    for ($i = 0; $i -lt 100; $i++) { try { $fs = [IO.File]::Open($path, 'Append', 'Write', 'ReadWrite, Delete'); try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }; return } catch { Start-Sleep -Milliseconds 50 } }
}
function WaitEv($who, [int]$from, [scriptblock]$cond, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do { $all = Events $who; for ($i = $from; $i -lt $all.Count; $i++) { if (& $cond $all[$i]) { return $all[$i] } }; Start-Sleep -Milliseconds 300 } while ((Get-Date) -lt $deadline)
    $null
}
function Count($who) { (Events $who).Count }
function CmdResult($who, $line, [int]$seconds = 8) { $f = Count $who; Cmd $who $line; WaitEv $who $f { param($x) $x.ev -eq 'command' -and $x.cmd -eq $line } $seconds }
function EndMission { foreach ($t in 1..6) { if (-not (Status 'host').onMission) { return }; Cmd 'host' 'failmission'; Start-Sleep 3 } }

# only this test's own game copies: never the game someone is playing
Get-Process gta_sa -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$GameDir*" -or $_.Path -like "$PartnerDir*" } | Stop-Process -Force
Start-Sleep 1
foreach ($w in 'host', 'partner') { New-Item -ItemType Directory -Force (AutoDir $w) | Out-Null; Remove-Item "$(AutoDir $w)\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
$crashDirs = @($LabCrashDir, (Join-Path $PartnerDir 'CoopAndreas_crashes'))
$crashes0 = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count
$work = Join-Path $env:TEMP "coopandreas-barberpair-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1675 13.5'; Start-Sleep 4
    if ($KillInMission) {
        # like quick-fixes 7b: the partner dies during mission 13 (it fails), then respawns
        [void](CmdResult 'host' 'startmission 13'); Start-Sleep 4; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 6
        [void](Wait-Playable { Status 'partner' } 40)
    }
    if ($KillFirst -or $KillInMission) {
        [void](CmdResult 'partner' 'kill'); Start-Sleep 3
        foreach ($t in 1..6) { if (-not (Status 'host').onMission) { break }; Cmd 'host' 'failmission'; Start-Sleep 3 }
        Write-Host "    partner playable again after $(Wait-Playable { Status 'partner' } 70) s"
    }
    Cmd 'host' 'enex BARBERS 1'; Cmd 'partner' 'enex BARBERS 1'
    Cmd 'host' 'teleport 2073.0 -1795.5 13.6'; Cmd 'partner' 'teleport 2074.0 -1796.5 13.6'; Start-Sleep 3
    $door = @((Status 'host').doors) | Where-Object { $_.name -eq 'BARBERS' -and $_.z -lt 500 } | Select-Object -First 1
    if ($door) {
        # one after the other: two CJs put on the same spot at once push each other off the door trigger
        Cmd 'host' ("teleport {0} {1} {2}" -f $door.x, $door.y, ($door.z + 0.6)); Start-Sleep 2; Cmd 'partner' ("teleport {0} {1} {2}" -f $door.x, $door.y, ($door.z + 0.6))
        Start-Sleep 9
        # the partner sits first (every player runs the shop script), then the host steps onto the same spot
        Cmd 'partner' 'teleport 414.3 -19.9 1001.3'
        $deadline = (Get-Date).AddSeconds(12); while (-not (Status 'partner').minigame -and (Get-Date) -lt $deadline) { Start-Sleep 1 }
        $pm = (Status 'partner').minigame
        Cmd 'host' 'teleport 414.5 -19.7 1001.3'; Start-Sleep 7
        $hm = (Status 'host').minigame
        Check 'Only one player at a time gets the barber chair' ($pm -and -not $hm) "partner seated=$pm, host seated=$hm, areas $((Status 'host').area)/$((Status 'partner').area)"
    }
    else { Check 'Only one player at a time gets the barber chair' $false 'BARBERS door not found' }
    $p = @((Status 'host').players)[0]; Write-Host "    host sees the partner: health $($p.health) state $($p.pedState) area $($p.interior) at $($p.x) $($p.y) $($p.z)"
}
catch { Check 'Barber test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
