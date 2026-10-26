# Quick checks for the bugs friends reported (2026-10-23), two real games (host + partner copy), ~5 minutes:
# marker start with a partner beside / far from the marker, wanted level stays per player, radio only in your
# own car, visible area follows the player, the barber shop has one barber for two players, saving/mission start
# with the host inside a house doesn't send partners into the sky.
#
#   powershell -ExecutionPolicy Bypass -File testing\quick-fixes.ps1

param([int]$Port = 16795, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\quick-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-quick-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

$host_ = $null; $partner = $null
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    Check 'Both games running' ([bool]((Status 'host').fps -gt 5 -and (Status 'partner').fps -gt 5)) ''

    # 0. NPC jitter on the partner's screen: the host's peds (Grove Street), old snapping vs smoothing, 20 s each
    Cmd 'host' 'teleport 2490 -1660 13.5'; Cmd 'partner' 'teleport 2492 -1660 13.5'; Start-Sleep 5
    Cmd 'partner' 'smoothing 0'; Start-Sleep 20
    $old = Status 'partner'
    Cmd 'partner' 'smoothing 1'; Start-Sleep 20
    $new = Status 'partner'
    # npcJitterCm = % of moving frames where a synced NPC steps backwards (snap-back); natural walking ~0%
    Check 'NPCs move smoothly on the partner screen (no snap-backs)' ($new.npcJitterSamples -gt 100 -and $new.npcJitterCm -le 1.0) `
        ("snap-backs {0:N1}% (old snapping) -> {1:N1}% ({2} / {3} moving frames)" -f $old.npcJitterCm, $new.npcJitterCm, $old.npcJitterSamples, $new.npcJitterSamples)

    # 1. marker: partner 2.6 m from Big Smoke's marker (was: everyone inside the 1 m marker)
    $hf = Count 'host'
    Cmd 'partner' 'teleport 2497.7 -1687.9 13.5'; Start-Sleep 1
    Cmd 'host' 'teleport 2495.214 -1687.03 13.5'
    $st = WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_started' } 25
    Check 'Marker starts the mission with the partner 2.6 m beside it' ([bool]$st) ''
    Start-Sleep 4; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 4; EndMission; Start-Sleep 6

    # 2. wanted level is per player
    Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1670 13.5'; Start-Sleep 2
    Cmd 'host' 'wanted 2'; Start-Sleep 4
    $hw = (Status 'host').local.wanted; $pw = (Status 'partner').local.wanted
    Check "Host's wanted level stays with the host" ($hw -ge 2 -and $pw -eq 0) "host=$hw partner=$pw"
    Cmd 'host' 'nowanted'; Start-Sleep 1

    # 3. radio: partner in a car, host on foot -> host hears no radio
    Start-Sleep 3
    $baseline = (Status 'host').radioCar
    Write-Host "    host radio before the partner's car: $baseline"
    [void](CmdResult 'partner' 'vehicle 400'); Start-Sleep 5
    $ps = Status 'partner'; $hs = Status 'host'
    Check "A partner's car radio doesn't play for the host on foot" ($ps.local.inVehicle -and $hs.radioCar -ne 'other') "partner inVehicle=$($ps.local.inVehicle) radio=$($ps.radioCar); host radio=$($hs.radioCar)"
    [void](CmdResult 'host' 'vehicle 400'); Start-Sleep 5
    Check 'The host still hears the radio in their own car' ((Status 'host').radioCar -eq 'mine') "radio=$((Status 'host').radioCar)"
    Cmd 'host' 'leavevehicle'; Cmd 'partner' 'leavevehicle'; Start-Sleep 3

    # 4. visible area follows the player: an interior area left on while standing outside is corrected
    $pf = Count 'partner'
    Cmd 'partner' 'interior 5'
    $ac = WaitEv 'partner' $pf { param($x) $x.ev -eq 'area_corrected' } 10
    Start-Sleep 1
    $ps = Status 'partner'
    Check 'Interior area shown while outside is corrected to the outside' ([bool]$ac -and $ps.area -eq 0) "area now $($ps.area); partner pad $($ps.pad | ConvertTo-Json -Compress) widescreen=$($ps.widescreen) onMission=$($ps.onMission)"

    # 5. barber: both walk in together -> one barber
    Cmd 'host' 'enex BARBERS 1'; Cmd 'partner' 'enex BARBERS 1'   # unlocked by the story later
    Cmd 'host' 'teleport 2073.0 -1795.5 13.6'; Cmd 'partner' 'teleport 2074.0 -1796.5 13.6'; Start-Sleep 3
    $door = @((Status 'host').doors) | Where-Object { $_.name -eq 'BARBERS' -and $_.z -lt 500 } | Select-Object -First 1
    if ($door) {
        # one after the other: two CJs put on the same spot at once push each other off the door trigger
        Cmd 'host' ("teleport {0} {1} {2}" -f $door.x, $door.y, ($door.z + 0.6)); Start-Sleep 2; Cmd 'partner' ("teleport {0} {1} {2}" -f $door.x, $door.y, ($door.z + 0.6))
        Start-Sleep 9
        $h = Status 'host'; $p = Status 'partner'
        $hc = (CmdResult 'host' 'countpeds 20 156 176 177').result; $pc = (CmdResult 'partner' 'countpeds 20 156 176 177').result
        Check 'Two players walking into the barber get one barber' ($h.local.interior -ne 0 -and $hc -eq 'count=1' -and $pc -eq 'count=1') "host area=$($h.local.interior) $hc, partner area=$($p.local.interior) $pc"
    }
    else { Check 'Two players walking into the barber get one barber' $false 'BARBERS door not found' }
    Cmd 'host' 'interior 0'; Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'interior 0'; Cmd 'partner' 'teleport 2499 -1670 13.5'; Start-Sleep 4

    # 6. host inside CJ's house + mission/save start + partner far away -> partner not moved into the sky
    Cmd 'host' 'enex CARLS 1'   # unlocked by passing Big Smoke
    Cmd 'host' 'teleport 2495.3 -1690.0 13.8'; Start-Sleep 2
    $d = @((Status 'host').doors) | Where-Object { $_.name -eq 'CARLS' -and $_.z -lt 500 } | Select-Object -First 1
    if ($d) { Cmd 'host' ("teleport {0} {1} {2}" -f $d.x, $d.y, ($d.z + 0.6)) }
    Start-Sleep 6
    Cmd 'partner' 'teleport 2300 -1650 14.5'; Start-Sleep 3
    $before = (Status 'partner').local
    $hf = Count 'host'
    Cmd 'host' 'startmission 13'
    Start-Sleep 8
    $after = (Status 'partner').local
    Check 'Host inside a house: far partner is not teleported into the sky' ((Status 'host').local.interior -ne 0 -and $after.z -lt 100) "host area=$((Status 'host').local.interior); partner z $([int]$before.z) -> $([int]$after.z)"
    EndMission

    # 7. extra car for partners (host's mission vehicle has no free seat): its blue marker goes once someone sits in it
    Cmd 'host' 'interior 0'; Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'interior 0'; Cmd 'partner' 'teleport 2499 -1675 13.5'; Start-Sleep 5
    $hf = Count 'host'
    Cmd 'host' 'startmission 13'; Start-Sleep 4; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 5
    Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2497 -1680 13.5'; Start-Sleep 3
    [void](CmdResult 'host' 'vehicle 571 mission')   # kart: driver only
    $pv = WaitEv 'host' $hf { param($x) $x.ev -eq 'partner_vehicles' } 10
    Start-Sleep 3
    $before = @((Status 'host').blips | Where-Object { $_.type -eq 1 }).Count
    $enter = (CmdResult 'partner' 'entermissioncar').result
    Start-Sleep 4
    $after = @((Status 'host').blips | Where-Object { $_.type -eq 1 }).Count
    $pin = (Status 'partner').local.inVehicle
    Check 'The extra partner car loses its marker once a player sits in it' ([bool]$pv -and $pin -and $after -lt $before) "spawned=$([bool]$pv), car markers $before -> $after, partner in a car=$pin ($enter)"
    Cmd 'partner' 'leavevehicle'; Cmd 'host' 'leavevehicle'; Start-Sleep 2
    EndMission; Start-Sleep 4

    # 7b. a partner who dies mid-mission and respawns is still one of the mission's partners (new ped handle)
    Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1675 13.5'; Start-Sleep 3
    $hf = Count 'host'
    Cmd 'host' 'startmission 13'
    if (WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_started' } 20) {
        Start-Sleep 4; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 6
        # 'kill' is a real deadly hit: the game ignores it during the mission's opening scene (no control)
        [void](Wait-Playable { Status 'partner' } 40)
        $hf = Count 'host'
        Cmd 'partner' 'kill'
        # coop missions fail for everyone when a partner dies (like the host's death); if a mission ever keeps going,
        # the host must switch to the respawned partner's new ped
        $ev = WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_partner_handle_updated' -or $x.ev -eq 'mission_failed' } 40
        $pf = $ev -and $ev.ev -eq 'mission_failed' -and (Events 'partner' | Where-Object { $_.ev -eq 'mission_failed' })
        Check 'A partner dying mid-mission: mission fails for all, or the partner stays in it' ($pf -or ($ev -and $ev.ev -eq 'mission_partner_handle_updated')) $(if ($ev) { "$($ev.ev)" } else { 'nothing happened' })
    }
    else { Check 'A partner who respawns mid-mission stays in the mission' $false 'mission 13 did not start' }
    EndMission; Start-Sleep 3
    # wait for the partner's own respawn ('heal' no longer revives a dead player: that broke the restart) and the
    # first-death hospital tutorial
    [void](Wait-Playable { Status 'partner' } 70)

    # 8. barber chair: while one player sits in it, another standing on the chair spot does not get seated too
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
}
catch { Check 'Quick checks run' $false $_.Exception.Message }
finally {
    $new = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($new -le 0) "$new"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
$LabResults | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $report 'report.json') -Encoding utf8
Write-Host ("{0} passed, {1} failed. Report: {2}" -f ($LabResults.Count - $failed), $failed, $report)
exit $failed
