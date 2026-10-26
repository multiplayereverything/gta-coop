# CoopAndreas test lab: a real game in --autotest mode + a server + headless bots, checked
# through the game's own event log (CoopAndreas\autotest\events.jsonl) and live status.json.
# Screenshots are taken only when a check fails (or always with -Shots).
#
#   powershell -ExecutionPolicy Bypass -File testing\lab.ps1                 # full run
#   powershell -ExecutionPolicy Bypass -File testing\lab.ps1 -Keep           # leave game+server up for lab-cmd.ps1
#                                                                             (don't pipe its output: the pipe waits for the game)
#   powershell -ExecutionPolicy Bypass -File testing\lab.ps1 -Bots 1 -Shots
#   powershell -ExecutionPolicy Bypass -File testing\lab.ps1 -Scenario mission   # only the Big Smoke mission test
#
# Scenarios: basic = connect, 3 bots walk/chat, car.  mission = first story mission with a 2nd player
# (marker trigger, cutscene + skip vote, scripted drive, 2nd cutscene, fail by death, what player 2 received).
#
# Results: testing\reports\<timestamp>\ (report.json, timeline.txt, events.jsonl, logs, screenshots on failure).
# Exit code = number of failed checks.

param(
    [int]$Port = 16768,
    [ValidateSet('all', 'basic', 'mission')][string]$Scenario = 'all',
    [ValidateRange(0, 3)][int]$Bots = 3,
    [int]$BootTimeout = 180,
    [switch]$Shots,
    [switch]$Keep,
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)')  # the test copy: never the game someone plays
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')

$report = Join-Path $PSScriptRoot ("reports\" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
New-Item -ItemType Directory -Force $report | Out-Null
$script:ReportDir = $report
$script:AlwaysShots = [bool]$Shots


# clean slate
Get-Process gta_sa, CoopAndreasBot -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*coopandreas-lab*" } | Stop-Process -Force
Start-Sleep -Milliseconds 500
New-Item -ItemType Directory -Force $LabAutoDir | Out-Null
Remove-Item "$LabAutoDir\*" -Recurse -Force -ErrorAction SilentlyContinue
$crashesBefore = @(Get-ChildItem $LabCrashDir -Filter *.log -ErrorAction SilentlyContinue).Count

$work = Join-Path $env:TEMP "coopandreas-lab-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Minimized `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
Set-Content (Join-Path $LabAutoDir 'lab.json') (@{ serverPid = $server.Id; port = $Port; report = $report } | ConvertTo-Json) -Encoding ascii

$t0 = Get-Date
$botProcs = @()
try {
    # --- boot + connect -------------------------------------------------------------------
    $script:Game = Start-Process (Join-Path $GameDir 'gta_sa.exe') -WorkingDirectory $GameDir -PassThru `
        -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname Tester"

    $e = Wait-Event 'game_loop_running' $BootTimeout
    Focus-Game  # an unfocused SA window may stop updating
    Check 'Coop per-frame code runs in game' ([bool]$e) $(if ($e) { $hk = @(Read-AllEvents | Where-Object { $_.ev -eq 'hook_reclaimed' }); "hook reclaimed from another mod: $($hk.Count -gt 0)" } else { Last-Events 6 })
    $e = Wait-Event 'authenticated' 20
    Check 'Boot, new game, connect, handshake' ([bool]$e) $(if ($e) { "id=$($e.id) after $([int]((Get-Date) - $t0).TotalSeconds)s" } else { Last-Events 6 })
    if (-not $e) { throw 'not connected' }
    $e = Wait-Event 'host_gained' 10
    Check 'First player becomes host' ([bool]$e) ''

    if ($Scenario -ne 'mission') {
    Send-Command 'teleport 2499 -1676 13.4'
    Wait-Event 'command' 5 { param($x) $x.cmd -like 'teleport*' } | Out-Null

    # --- bots join --------------------------------------------------------------------------
    if ($Bots -gt 0) {
        for ($b = 1; $b -le $Bots; $b++) {
            $botProcs += Start-Process (Join-Path $LabBin 'CoopAndreasBot.exe') -PassThru -WindowStyle Hidden `
                -ArgumentList "--port $Port --name Bot$b --index $b --duration 30 --expect-peers $Bots" `
                -RedirectStandardOutput (Join-Path $report "Bot$b.log") -RedirectStandardError (Join-Path $report "Bot$b.err")
        }
        $peds = Wait-Events 'player_ped_created' $Bots 15
        Check "$Bots bots joined and got a ped" ($peds.Count -eq $Bots) (($peds | ForEach-Object { "$($_.name)@$($_.x),$($_.y)" }) -join '; ')

        # sample positions for up to 8 s and record when each bot ped first moves (a long delay = sync freeze)
        Focus-Game
        $joinedAt = Get-Date
        $first = @{}; $startMove = @{}
        while (((Get-Date) - $joinedAt).TotalSeconds -lt 8 -and $startMove.Count -lt $Bots) {
            $s = Wait-StatusAdvance (Read-Status) 400 2
            foreach ($p in @($s.players | Where-Object { $_.hasPed })) {
                if (-not $first.ContainsKey($p.name)) { $first[$p.name] = $p; continue }
                $o = $first[$p.name]
                if (-not $startMove.ContainsKey($p.name) -and ([math]::Abs($p.x - $o.x) + [math]::Abs($p.y - $o.y)) -gt 0.3) {
                    $startMove[$p.name] = ((Get-Date) - $joinedAt).TotalSeconds
                }
            }
        }
        $slow = @($startMove.Values | Where-Object { $_ -gt 3 })
        Check 'Bot peds walk in game' ($startMove.Count -eq $Bots) (($startMove.GetEnumerator() | Sort-Object Name | ForEach-Object { '{0} moving after {1:N1}s' -f $_.Name, $_.Value }) -join ', ')
        Check 'Bot peds start moving within 3 s of joining' ($startMove.Count -eq $Bots -and $slow.Count -eq 0) "$($slow.Count) slow"

        $chats = Wait-Events 'chat_received' $Bots 8 { param($x) $x.text -like 'hello from Bot*' }
        Check 'Game receives bot chat' ($chats.Count -ge $Bots) (($chats | ForEach-Object { "$($_.from): $($_.text)" }) -join ' | ')
        Send-Command 'chat hello from the real game'
    }

    # --- car ------------------------------------------------------------------------------
    Send-Command 'vehicle 411'
    $e = Wait-Event 'vehicle_entered' 8
    Check 'Spawn car and get in' ([bool]$e) $(if ($e) { "model=$($e.model)" } else { Last-Events 4 })
    Start-Sleep 1
    $s = Read-Status
    Check 'Car is a network vehicle' ($s.networkVehicles -ge 1) "networkVehicles=$($s.networkVehicles)"
    Send-Command 'teleport 2480 -1660 13.4'
    Send-Command 'leavevehicle'
    $e = Wait-Event 'vehicle_exited' 8
    Check 'Leave car' ([bool]$e) ''

    # --- bots report what they saw of the real game -------------------------------------
    if ($Bots -gt 0) {
        $botProcs | ForEach-Object { $_.WaitForExit(45000) | Out-Null }
        foreach ($b in 1..$Bots) {
            $line = Get-Content (Join-Path $report "Bot$b.log") -ErrorAction SilentlyContinue | Where-Object { $_ -like 'RESULT *' } | Select-Object -Last 1
            $r = if ($line) { $line.Substring(7) | ConvertFrom-Json } else { $null }
            $tester = if ($r) { $r.peers | Where-Object { $_.name -eq 'Tester' } } else { $null }
            Check "Bot$b sees the real game move + chat" ([bool]($tester -and $tester.onfoot -ge 20 -and $tester.chat -ge 1)) `
                $(if ($tester) { "onfoot=$($tester.onfoot) chat=$($tester.chat)" } else { 'Tester not seen' })
        }
        $left = Wait-Events 'player_left' $Bots 10
        Check 'Bots removed after leaving' ($left.Count -eq $Bots) "$($left.Count)/$Bots"
    }
    }

    # --- first story mission: Big Smoke (INTRO1) with a second player ---------------------------
    if ($Scenario -ne 'basic') {
        # Player2 stands in the Big Smoke marker ($introX/Y/Z in scm/scripts/INITIAL.txt) and votes to skip cutscenes
        $p2Log = Join-Path $report 'Player2.log'
        $botProcs += Start-Process (Join-Path $LabBin 'CoopAndreasBot.exe') -PassThru -WindowStyle Hidden `
            -ArgumentList '--port', $Port, '--name', 'Player2', '--duration', '180', '--no-chat', '--vote-skip', '--stand', '2495.6', '-1687.4', '13.5' `
            -RedirectStandardOutput $p2Log -RedirectStandardError (Join-Path $report 'Player2.err')
        $e = Wait-Event 'player_ped_created' 15 { param($x) $x.name -eq 'Player2' }
        Check 'Player2 joins for the mission' ([bool]$e) ''

        # the trigger (scm/scripts/INT.txt) needs ALL players on foot in the marker: Coop.LocateAllPlayersOnFoot3D
        Send-Command 'teleport 2494.9 -1686.8 13.5'
        $e = Wait-Event 'mission_started' 20
        $diag = ''
        if (-not $e) {
            $s = Read-Status
            $p2 = $s.players | Where-Object { $_.name -eq 'Player2' }
            $diag = "host=$($s.local.x),$($s.local.y),$($s.local.z) car=$($s.local.inVehicle) wanted=$($s.local.wanted) onMission=$($s.onMission) mission=$($s.mission) p2=$($p2.x),$($p2.y),$($p2.z) d=$($p2.distance); retried"
            Send-Command 'teleport 2494.9 -1686.8 13.5'
            $e = Wait-Event 'mission_started' 20
        }
        Check 'Both players in the marker start Big Smoke' ([bool]$e) $(if ($e) { "host=$($e.host) $diag" } else { "$diag | $(Last-Events 5)" })

        $cs = Wait-Event 'cutscene_started' 20
        Check 'Intro cutscene INTRO1A plays' ($cs -and $cs.name -eq 'INTRO1A') "name=$($cs.name)"
        $v = Wait-Event 'skip_vote_state' 8 { param($x) $x.voters -eq 2 -and $x.votes -ge 1 }
        Check 'Skip vote counts 2 voters and Player2 voted' ([bool]$v) $(if ($v) { "$($v.votes)/$($v.voters)" } else { Last-Events 4 })
        Start-Sleep 1
        Check 'Cutscene keeps playing until everyone voted' ((Read-Status).cutscene -eq 'INTRO1A') "cutscene=$((Read-Status).cutscene)"

        $hid = @(Read-AllEvents | Where-Object { $_.ev -eq 'players_hidden' })
        Check "Other players' CJs hidden during the cutscene" ($hid.Count -ge 1) $(if ($hid) { "hidden=$($hid[-1].count)" } else { 'none' })

        Send-Command 'skipcutscene'
        $e = Wait-Event 'cutscene_ended' 10
        Check 'Host vote completes 2/2 and skips INTRO1A' ($e -and $e.skipped) $(if ($e) { "skipped=$($e.skipped)" } else { Last-Events 4 })

        # the script continues to INTRO1B (sometimes within seconds); search the whole log for it
        $deadline = (Get-Date).AddSeconds(60); $idx = -1; $all = @()
        while ($idx -lt 0 -and (Get-Date) -lt $deadline) {
            $all = @(Read-AllEvents)
            for ($i = 0; $i -lt $all.Count; $i++) { if ($all[$i].ev -eq 'cutscene_started' -and $all[$i].name -eq 'INTRO1B') { $idx = $i; break } }
            if ($idx -lt 0) { Start-Sleep -Milliseconds 300 }
        }
        Check 'Mission script continues to INTRO1B' ($idx -ge 0) ''
        if ($idx -ge 0) {
            Send-Command 'skipcutscene'
            Start-Sleep 3
            $all = @(Read-AllEvents)
            $end = $all[($idx + 1)..($all.Count - 1)] | Where-Object { $_.ev -eq 'cutscene_ended' } | Select-Object -First 1
            Check 'INTRO1B skipped by vote' ([bool]($end -and $end.skipped)) ''
            $script:EventCursor = $all.Count
        }

        # fail it: a player can't die during a cutscene, so wait for control first
        Start-Sleep 3
        Send-Command 'kill'
        $e = Wait-Event 'mission_failed' 30
        Check 'Host death fails the mission (M_FAIL)' ([bool]$e) $(if ($e) { "gxt=$($e.gxt)" } else { Last-Events 5 })
        # mission_ended is logged in the same frame as (often just before) mission_failed, so look at the whole log
        $ended = @(Read-AllEvents | Where-Object { $_.ev -eq 'mission_ended' })
        Check 'Mission ends on the host' ($ended.Count -ge 1) ''
        $e = Wait-Event 'alive' 20
        Check 'Host respawns after the fail' ([bool]$e) $(if ($e) { "at $($e.x),$($e.y)" } else { '' })
        # scripted scenes (widescreen, no control) keep the other CJs hidden; by now they must be visible again
        $deadline = (Get-Date).AddSeconds(45)   # death fade + first-death hospital tutorial are scripted scenes (slower minimized)
        do {
            Start-Sleep 1
            $hs = @(Read-AllEvents | Where-Object { $_.ev -in 'players_hidden', 'players_shown' })
        } while ((Get-Date) -lt $deadline -and $hs.Count -gt 0 -and $hs[-1].ev -ne 'players_shown')
        Check "Other players' CJs visible again after the scenes" ($hs.Count -gt 0 -and $hs[-1].ev -eq 'players_shown') "last=$($hs[-1].ev)"

        # what Player2 received over the network
        Start-Sleep 2
        $botProcs | Where-Object { -not $_.HasExited } | Stop-Process -Force
        $mline = Get-Content $p2Log -ErrorAction SilentlyContinue | Where-Object { $_ -like 'MISSION *' } | Select-Object -Last 1
        $m = if ($mline) { $mline.Substring(8) | ConvertFrom-Json } else { $null }
        Check 'Player2 got mission start + end flags' ([bool]($m -and $m.onMissionFlags -match '1.*0')) "flags=$($m.onMissionFlags)"
        Check 'Player2 got the cutscene (load + start opcodes)' ([bool]($m -and $m.loadCutscene -and $m.startCutscene)) "load=$($m.loadCutscene) start=$($m.startCutscene) opcodes=$($m.opcodes)"
        Check 'Player2 voted in both cutscenes' ([bool]($m -and $m.votesSent -ge 2 -and $m.maxVoters -eq 2)) "votesSent=$($m.votesSent) maxVoters=$($m.maxVoters)"
        Check 'Player2 got the mission texts' ([bool]($m -and $m.gxt)) "gxt=$($m.gxt)"
        # KNOWN GAP (upstream): mission scripts print M_FAIL/M_PASS with plain Text.PrintBig, which is not synced
        Known 'Player2 sees the MISSION FAILED banner' ([bool]($m -and $m.gxt -match 'M_FAIL')) 'scripts print M_FAIL locally only; see MODLOG'
    }

    Check 'Game still running' (-not $script:Game.HasExited) "fps=$((Read-Status).fps)"
}
catch {
    Check 'Lab run' $false $_.Exception.Message
}
finally {
    $crashes = @(Get-ChildItem $LabCrashDir -Filter *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    $new = $crashes.Count - $crashesBefore
    Check 'No new crash logs' ($new -le 0) $(if ($new -gt 0) { ($crashes | Select-Object -Last $new | ForEach-Object Name) -join ', ' } else { 'none' })
    if ($new -gt 0) {
        $crashes | Select-Object -Last $new | Copy-Item -Destination $report
        $first = Get-Content ($crashes | Select-Object -Last 1).FullName -TotalCount 3
        Write-Host "  crash: $($first -join ' / ')"
    }
    Copy-Item (Join-Path $LabAutoDir 'events.jsonl'), (Join-Path $LabAutoDir 'status.json') $report -ErrorAction SilentlyContinue
    Write-Timeline (Join-Path $report 'timeline.txt')
    $botProcs | Where-Object { -not $_.HasExited } | Stop-Process -Force
    if (-not $Keep) {
        if ($script:Game -and -not $script:Game.HasExited) { Stop-Process -Id $script:Game.Id -Force }
        if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    }
}

$failed = @($LabResults | Where-Object { -not $_.pass }).Count
$LabResults | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $report 'report.json') -Encoding utf8
Write-Host ''
Write-Host ("{0} passed, {1} failed in {2}s. Report: {3}" -f ($LabResults.Count - $failed), $failed, [int]((Get-Date) - $t0).TotalSeconds, $report)
if ($Keep) { Write-Host 'Game + server left running: use testing\lab-cmd.ps1 "<command>"' }
exit $failed
