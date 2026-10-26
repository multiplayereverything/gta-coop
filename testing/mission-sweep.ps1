# 4-player mission sweep: a test game copy (host) + 3 bots run through missions one by one.
# Per mission: start it (startmission <id>), skip every cutscene by vote (bots vote, then the host),
# let it run, fail it by killing the host, wait for respawn. Records what the host saw (events) and what the
# other players received (bot MISSION counters). Restarts the game after crashes or stuck missions.
#
#   powershell -ExecutionPolicy Bypass -File testing\mission-sweep.ps1                    # story missions 11-112
#   powershell -ExecutionPolicy Bypass -File testing\mission-sweep.ps1 -Missions "11,12,16"
#   powershell -ExecutionPolicy Bypass -File testing\mission-sweep.ps1 -Missions "113-134"  # side missions
#
# Output: testing\reports\sweep-<time>\ missions.json, missions.md, per-mission timelines, crash logs.
# This is a smoke test (does it start, sync and end cleanly with 4 players), not a full playthrough.

param(
    [string]$Missions = '11-112',   # ids and ranges: "11-20,35,40-45"
    [int]$Port = 16769,
    [int]$RunSeconds = 15,
    # pass: end each mission through its own pass routine (autotest passmission), falls back to fail
    [ValidateSet('fail', 'death', 'pass')][string]$EndBy = 'fail',
    # the test copy: never the game someone plays
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')

$MissionIds = @($Missions -split ',' | Where-Object { $_.Trim() } | ForEach-Object {
    $p = $_.Trim() -split '-'
    if ($p.Count -eq 2) { [int]$p[0]..[int]$p[1] } else { [int]$p[0] }
})

$root = Split-Path -Parent $PSScriptRoot
$report = Join-Path $PSScriptRoot ("reports\sweep-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
New-Item -ItemType Directory -Force $report | Out-Null
$script:ReportDir = $report

# per-mission setup = what the player has at the real trigger
$MissionPrep = @{
    36 = @('teleport 1800 -1930 13.5', 'vehicle 567')   # Lowrider (High Stakes): you arrive in a lowrider; on foot the game closed
}

$names = @{}
Select-String -Path (Join-Path $root 'CoopAndreas\scm\main.txt') -Pattern '^DEFINE MISSION (\d+) AT @(\w+)\s+//\s*(.*)$' | ForEach-Object {
    $g = $_.Matches[0].Groups
    $names[[int]$g[1].Value] = @{ label = $g[2].Value; name = $g[3].Value.Trim() }
}

$work = Join-Path $env:TEMP "coopandreas-sweep-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii

# only this sweep's own processes are ever stopped, so two sweeps (mission-sweep-parallel.ps1) can run side by side
$script:Game = $null
$script:Server = $null
$script:Bots = @()
$script:Boots = 0

# killed bots never send a disconnect, the server would keep their slots (and maybe the host role) for 30 s:
# every session gets a fresh server
function Restart-Server {
    if ($script:Server -and -not $script:Server.HasExited) { Stop-Process -Id $script:Server.Id -Force; Start-Sleep 1 }
    $script:Server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Minimized `
        -RedirectStandardOutput (Join-Path $report "server-$($script:Boots + 1).log") -RedirectStandardError (Join-Path $report 'server.err')
    Start-Sleep 1
}

function Get-EventCount { @(Read-AllEvents).Count }
function Get-EventsSince([int]$from) { $all = @(Read-AllEvents); if ($all.Count -gt $from) { $all[$from..($all.Count - 1)] } else { @() } }

function Wait-For([int]$from, [scriptblock]$cond, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do {
        $hit = Get-EventsSince $from | Where-Object { & $cond $_ } | Select-Object -First 1
        if ($hit) { return $hit }
        if ($script:Game.HasExited) { return $null }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $null
}

function Read-BotMission([int]$i) {
    $line = Get-Content (Join-Path $report "Mate$i.log") -ErrorAction SilentlyContinue | Where-Object { $_ -like 'MISSION *' } | Select-Object -Last 1
    if ($line) { $line.Substring(8) | ConvertFrom-Json } else { [pscustomobject]@{ onMissionFlags = ''; texts = 0; cutscenes = 0; votesSent = 0; failBanners = 0; passBanners = 0; teleports = 0 } }
}

# (re)start the game as host, then the 3 bots (bots first would make a bot the host)
function Start-Session {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $script:Bots | Where-Object { -not $_.HasExited } | Stop-Process -Force -ErrorAction SilentlyContinue
        if ($script:Game -and -not $script:Game.HasExited) { Stop-Process -Id $script:Game.Id -Force }
        Start-Sleep 2
        Restart-Server
        New-Item -ItemType Directory -Force $LabAutoDir | Out-Null
        Remove-Item "$LabAutoDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        $script:EventCursor = 0
        $script:Boots++
        $script:Game = Start-Process (Join-Path $GameDir 'gta_sa.exe') -WorkingDirectory $GameDir -PassThru `
            -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname Host"
        if (Wait-For 0 { param($e) $e.ev -eq 'host_gained' } 90) { break }
        Write-Host "  boot attempt $attempt failed: $(Last-Events 4)"
        if ($attempt -eq 3) { throw 'game did not become host after 3 attempts' }
    }
    Focus-Game
    $script:Bots = @()
    foreach ($b in 1..3) {
        $script:Bots += Start-Process (Join-Path $LabBin 'CoopAndreasBot.exe') -PassThru -WindowStyle Hidden `
            -ArgumentList '--port', $Port, '--name', "Mate$b", '--duration', '36000', '--no-chat', '--vote-skip', '--stand', (2490 + $b), '-1680', '13.5' `
            -RedirectStandardOutput (Join-Path $report "Mate$b.log") -RedirectStandardError (Join-Path $report "Mate$b.err")
    }
    $n = 0; $deadline = (Get-Date).AddSeconds(20)
    while ($n -lt 3 -and (Get-Date) -lt $deadline) { $n = @(Read-AllEvents | Where-Object { $_.ev -eq 'player_ped_created' }).Count; Start-Sleep -Milliseconds 300 }
    # let the new-game setup (INITIAL mission, streaming, radio) finish: starting a cutscene right after boot
    # crashed SilentPatch's audio stream thread (silentpatchsa.asi+0xAAC0) on Big Smoke
    Start-Sleep 15
    # a fresh save has San Fierro/Las Venturas locked: later missions would give CJ 4 stars every time
    Send-Command 'nowanted'
    Write-Host "  session $($script:Boots): host + $n bots"
}

$results = New-Object System.Collections.ArrayList
$crashDirCount = { @(Get-ChildItem $LabCrashDir -Filter *.log -ErrorAction SilentlyContinue).Count }

try {
    Start-Session
    foreach ($id in $MissionIds) {
        $info = $names[$id]
        $label = if ($info) { $info.label } else { "?" }
        $title = if ($info) { $info.name } else { "?" }
        Write-Host ("[{0,3}] {1,-8} {2}" -f $id, $label, $title)

        if ($script:Game.HasExited) { Start-Session }
        $crashes0 = & $crashDirCount
        $bot0 = Read-BotMission 1
        $from = Get-EventCount
        $t0 = Get-Date
        $r = [ordered]@{ id = $id; label = $label; name = $title; script = ''; ported = $false; started = $false
            cutscenes = @(); cutscenesSkipped = 0; cutsceneStuck = $false; endedBy = ''; botsSawStart = $false; botsSawEnd = $false
            botTexts = 0; botCutscenes = 0; botVotes = 0; botBanners = 0; botTeleports = 0; partnerCars = 0; crash = ''; restarted = $false; seconds = 0; notes = '' }

        Send-Command 'heal'
        # real-play setup some missions need at their trigger (launched on foot they behave differently)
        if ($MissionPrep.ContainsKey($id)) { foreach ($c in $MissionPrep[$id]) { Send-Command $c; Start-Sleep 2 } }
        # retry while a previous/initial mission script is still finishing (launching then would crash)
        $cmd = $null
        for ($try = 0; $try -lt 15; $try++) {
            $mark = Get-EventCount
            Send-Command "startmission $id"
            $cmd = Wait-For $mark { param($e) $e.ev -eq 'command' -and $e.cmd -eq "startmission $id" } 10
            if (-not $cmd -or $cmd.result -eq 'ok') { break }
            # a previous mission script that never ended blocks every later mission: fail it
            if ($cmd.result -like 'mission script running*' -and $try -ge 2) { Send-Command 'failmission' }
            Start-Sleep 2
        }
        if ($cmd -and $cmd.result -ne 'ok') { $r.notes = "startmission: $($cmd.result)" }
        # no answer at all: the game stopped reading commands (hung after CATCUT once, so every later mission
        # "did not start"); restart it after this mission
        if (-not $cmd) { $r.notes = 'game did not answer startmission'; $r.unresponsive = $true }
        $st = Wait-For $from { param($e) $e.ev -eq 'mission_started' } 12
        $r.started = [bool]$st
        $sc = Wait-For $from { param($e) $e.ev -eq 'mission_script' } 3
        if ($sc) { $r.script = $sc.script; $r.ported = [bool]$sc.synced }

        if ($r.started) {
            # run: skip every cutscene by vote, watch for the mission ending on its own
            $deadline = (Get-Date).AddSeconds($RunSeconds)
            $enterCarAt = (Get-Date).AddSeconds(8)   # then act like a player: get into the mission vehicle
            $seen = $from
            while ((Get-Date) -lt $deadline -and -not $script:Game.HasExited) {
                $new = @(Get-EventsSince $seen); $seen += $new.Count
                foreach ($e in $new) {
                    if ($e.ev -eq 'cutscene_started') {
                        $r.cutscenes += $e.name
                        Start-Sleep -Milliseconds 1500   # let the bots vote first
                        Send-Command 'skipcutscene'
                        $end = Wait-For $seen { param($x) $x.ev -eq 'cutscene_ended' } 15
                        if ($end) { if ($end.skipped) { $r.cutscenesSkipped++ } } else { $r.cutsceneStuck = $true }
                        $deadline = $deadline.AddSeconds(5)
                    }
                    if ($e.ev -eq 'mission_failed') { $r.endedBy = 'failed by itself' }
                    if ($e.ev -eq 'mission_passed') { $r.endedBy = 'passed' }
                }
                if ($r.endedBy -or $r.cutsceneStuck) { break }
                if ($enterCarAt -and (Get-Date) -gt $enterCarAt -and -not (Read-Status).cutscene) { Send-Command 'entermissioncar'; $enterCarAt = $null }
                Start-Sleep -Milliseconds 300
            }

            # end it. Default: fail_current_mission (fast, CJ stays alive). -EndBy death kills the host instead
            # (slower: death + hospital respawn ~10 s), which also tests that a death fails the mission.
            if (-not $r.endedBy -and -not $script:Game.HasExited) {
                $s = Read-Status
                if ($s.cutscene) { Send-Command 'skipcutscene'; Start-Sleep 3 }
                $f = $null
                if ($EndBy -eq 'pass') {
                    # the mission's own debug skip (autotest passmission) -> its real pass routine; the check sits in
                    # one of its main loops, so give it time and keep skipping cutscenes meanwhile
                    Send-Command 'passmission'
                    $deadline = (Get-Date).AddSeconds(60)
                    do {
                        $f = Wait-For $from { param($e) $e.ev -eq 'mission_passed' -or $e.ev -eq 'mission_failed' } 3
                        if (-not $f -and (Read-Status).cutscene) { Send-Command 'skipcutscene' }
                    } while (-not $f -and (Get-Date) -lt $deadline -and -not $script:Game.HasExited)
                    if ($f) { $r.endedBy = if ($f.ev -eq 'mission_passed') { "passed ($($f.gxt))" } else { 'failed by itself' } }
                    else { $r.notes = ($r.notes + ' no debug pass reached in 60 s').Trim(); $f = $null }
                    if (-not $f) { Send-Command 'failmission'; $f = Wait-For $from { param($e) $e.ev -eq 'mission_failed' -or $e.ev -eq 'mission_ended' } 15 }
                }
                elseif ($EndBy -eq 'fail') {
                    Send-Command 'failmission'
                    $f = Wait-For $from { param($e) $e.ev -eq 'mission_failed' -or $e.ev -eq 'mission_ended' } 15
                    if ($f) { $r.endedBy = 'failed (fail_current_mission)' }
                }
                if (-not $f) {
                    if ($s.local.inVehicle) { Send-Command 'leavevehicle'; Start-Sleep 1 }
                    Send-Command 'kill'
                    $f = Wait-For $from { param($e) $e.ev -eq 'mission_failed' -or $e.ev -eq 'mission_passed' } 35
                    if ($f) { $r.endedBy = if ($f.ev -eq 'mission_failed') { 'failed (host killed)' } else { 'passed' } }
                    else { $r.notes = ($r.notes + ' does not end by death or fail_current_mission').Trim() }
                }
            }
            $ended = Wait-For $from { param($e) $e.ev -eq 'mission_ended' } 15
            if (-not $ended) { $r.notes = ($r.notes + ' still on mission').Trim() }
            if (Get-EventsSince $from | Where-Object { $_.ev -eq 'wasted' }) {
                Wait-For $from { param($e) $e.ev -eq 'alive' } 25 | Out-Null
            }
            Start-Sleep 1
        }

        $bot1 = Read-BotMission 1
        $flags = ($bot1.onMissionFlags).Substring([math]::Min($bot0.onMissionFlags.Length, $bot1.onMissionFlags.Length))
        $r.botsSawStart = $flags -match '1'
        $r.botsSawEnd = $flags -match '10'
        $r.botTexts = $bot1.texts - $bot0.texts
        $r.botCutscenes = $bot1.cutscenes - $bot0.cutscenes
        $r.botVotes = $bot1.votesSent - $bot0.votesSent
        $r.botBanners = ($bot1.failBanners + $bot1.passBanners) - ($bot0.failBanners + $bot0.passBanners)
        $r.botTeleports = $bot1.teleports - $bot0.teleports
        $r.partnerCars = (@(Get-EventsSince $from | Where-Object { $_.ev -eq 'partner_vehicles' } | ForEach-Object { $_.count }) | Measure-Object -Sum).Sum

        $newCrashes = (& $crashDirCount) - $crashes0
        if ($script:Game.HasExited -or $newCrashes -gt 0) {
            $c = Get-ChildItem $LabCrashDir -Filter *.log | Sort-Object LastWriteTime | Select-Object -Last 1
            $r.crash = if ($newCrashes -gt 0) { (Get-Content $c.FullName -TotalCount 2) -join ' / ' } else { 'game exited' }
            if ($newCrashes -gt 0) { Copy-Item $c.FullName (Join-Path $report "crash-$id.log") }
        }
        $st2 = Read-Status
        if (-not $st2.onMission -and $st2.mission) {
            # a mission script still runs without the on-mission flag (e.g. farlie4): fail it before the next one
            Send-Command 'failmission'; Start-Sleep 5; $st2 = Read-Status
            if ($st2.mission) { $r.notes = ($r.notes + " leftover script $($st2.mission)").Trim() }
        }
        # anything left running (e.g. the Lowrider minigame ignores death and fail_current_mission) must not get
        # another mission launched on top of it: that overwrites mission code and crashes (gta_sa+0x6952A)
        $stuck = $st2.onMission -or [bool]$st2.mission -or $r.notes -like '*still on mission*' -or $r.unresponsive
        if ($script:Game.HasExited -or $newCrashes -gt 0 -or $stuck -or $r.cutsceneStuck) {
            $r.restarted = $true
            Write-Timeline (Join-Path $report "timeline-$id.txt")
            Start-Session
        }
        $r.seconds = [int]((Get-Date) - $t0).TotalSeconds
        [void]$results.Add([pscustomobject]$r)
        Write-Host ("      started={0} ported={1} cutscenes={2}/{3} ended='{4}' bots: start={5} end={6} texts={7} votes={8} banners={9} teleports={10} partnerCars={11} {12}" -f `
            $r.started, $r.ported, $r.cutscenesSkipped, $r.cutscenes.Count, $r.endedBy, $r.botsSawStart, $r.botsSawEnd, $r.botTexts, $r.botVotes, $r.botBanners, $r.botTeleports, $r.partnerCars, $(if ($r.crash) { "CRASH: $($r.crash)" } else { $r.notes }))
        $results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $report 'missions.json') -Encoding utf8
    }
}
finally {
    $script:Bots | Where-Object { -not $_.HasExited } | Stop-Process -Force -ErrorAction SilentlyContinue
    if ($script:Game -and -not $script:Game.HasExited) { Stop-Process -Id $script:Game.Id -Force }
    if ($script:Server -and -not $script:Server.HasExited) { Stop-Process -Id $script:Server.Id -Force }

    $md = @('| # | Script | Mission | Ported | Starts | Cutscenes skipped | Ends | Others see start/end | Others get texts | Others vote | Crash |',
            '|---|---|---|---|---|---|---|---|---|---|---|')
    foreach ($r in $results) {
        $md += "| $($r.id) | $($r.label) | $($r.name) | $(if ($r.ported) {'yes'} else {'no'}) | $(if ($r.started) {'yes'} else {'NO'}) | $($r.cutscenesSkipped)/$($r.cutscenes.Count)$(if ($r.cutsceneStuck) {' STUCK'}) | $($r.endedBy) | $(if ($r.botsSawStart) {'yes'} else {'no'})/$(if ($r.botsSawEnd) {'yes'} else {'no'}) | $($r.botTexts) | $($r.botVotes) | $(if ($r.crash) {'CRASH'} else {''}) |"
    }
    $md | Set-Content (Join-Path $report 'missions.md') -Encoding utf8
    Write-Host "Sweep done: $($results.Count) missions, game sessions: $($script:Boots). Report: $report"
}
