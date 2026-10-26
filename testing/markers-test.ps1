# Race checkpoints of a host-run mission show for the partner and disappear with the host's, 3 rounds (same id reused).
#   powershell -ExecutionPolicy Bypass -File testing\markers-test.ps1
param([int]$Port = 16794, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\markers-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-markers-$Port"
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
    Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1670 13.5'; Start-Sleep 3
    $hf = Count 'host'
    Cmd 'host' 'startmission 13'
    if (-not (WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_started' } 20)) { throw 'mission 13 did not start' }
    Start-Sleep 4; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 6
    foreach ($round in 1..3) {
        Cmd 'host' "checkpoint create $(2500 + $round * 5) -1665 13.5"; Start-Sleep 3
        $h = @((Status 'host').checkpoints).Count; $ps = Status 'partner'; $p = @($ps.checkpoints).Count; Write-Host "    partner mirrored=$($ps.mirroredMarkers) checkpoints=$($ps.checkpoints | ConvertTo-Json -Compress) host mirroring=$((Status 'host').mirroredMarkers)"
        Cmd 'host' 'checkpoint delete'; Start-Sleep 3
        $h2 = @((Status 'host').checkpoints).Count; $p2 = @((Status 'partner').checkpoints).Count
        Check "Race checkpoint shows for the partner and goes away (round $round)" ($h -eq 1 -and $p -eq 1 -and $h2 -eq 0 -and $p2 -eq 0) "shown host/partner $h/$p, after delete $h2/$p2"
    }

    # mission pickup: the partner sees a copy, walking over it gives the partner the item and the host's script
    # sees its pickup collected (armour 1242 next to the partner)
    Cmd 'partner' 'teleport 2499 -1672 13.5'; Start-Sleep 2
    [void](CmdResult 'host' 'pickup create 1242 2503 -1672 13.6')
    Start-Sleep 3
    $pc = (Status 'partner').missionPickups; $hc = (Status 'host').missionPickups
    $armour0 = (Status 'partner').local.armour
    $hf = Count 'host'
    Cmd 'partner' 'teleport 2503 -1672 13.6'; Start-Sleep 4
    $taken = WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_pickup_taken_by_partner' } 6
    $state = (CmdResult 'host' 'pickup state').result
    Start-Sleep 2
    Check 'Mission pickup shows for the partner, and the partner can collect it for the mission' ($hc -eq 1 -and $pc -eq 1 -and [bool]$taken -and $state -eq 'collected=true') "host sends $hc, partner copies $pc; host saw it taken: $([bool]$taken); $state; host now sends $((Status 'host').missionPickups)"

    # mission fire: burns for the partner too; the partner putting it out puts the host's out
    Cmd 'partner' 'teleport 2499 -1672 13.5'; Start-Sleep 1
    [void](CmdResult 'host' 'fire create 2506 -1680 13.5')
    Start-Sleep 3
    $hf0 = (Status 'host').missionFires; $pf0 = (Status 'partner').missionFires
    $hf = Count 'host'
    Cmd 'partner' 'fire out 2506 -1680 13.5'
    $out = WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_fire_out_by_partner' } 8
    $fstate = (CmdResult 'host' 'fire state').result
    Check 'Mission fire burns for the partner, and the partner can put it out' ($hf0 -eq 1 -and $pf0 -eq 1 -and [bool]$out -and $fstate -eq 'burning=false') "host sends $hf0, partner copies $pf0; host fire put out: $([bool]$out); $fstate"
    EndMission

    # train at Unity Station: the partner gets the same train, running in step with the host's
    Cmd 'host' 'teleport 1745 -1945 13.6'; Cmd 'partner' 'teleport 1748 -1945 13.6'; Start-Sleep 4
    $tr = (CmdResult 'host' 'train 1716 -1954 14 15').result
    Start-Sleep 3
    $t0 = (Status 'partner').trains
    Start-Sleep 10
    $hs = Status 'host'; $ps = Status 'partner'
    Write-Host "    host: $($hs.trainInfo)"; Write-Host "    partner: $($ps.trainInfo)"
    Check 'A train the host has also runs for the partner, in step' ($hs.trains -ge 1 -and $t0 -ge 1 -and $ps.trains -ge 1 -and $ps.trainOffset -lt 15) ("host trains {0}, partner {1} -> {2}; partner's train {3:N1} m from the host's ({4})" -f $hs.trains, $t0, $ps.trains, $ps.trainOffset, $tr)
    Cmd 'host' 'train delete'; Start-Sleep 3
    $ht = (Status 'host').trains; $pt = (Status 'partner').trains
    Check "When the host's train is deleted, the partner's goes too" ($pt -eq $ht) "trains now host $ht, partner $pt (the host's random trains are mirrored too)"
}
catch { Check 'Marker test runs' $false $_.Exception.Message }
finally {
    $new = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($new -le 0) "$new"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
