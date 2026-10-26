# Duo lab: TWO real games on this PC (host + partner), each in --autotest mode with its own folder
# (CoopAndreas\autotest\host, ...\partner). Verifies what a real partner client shows, which bots can't:
# the other player's ped, an unported mission's cutscene playing + skippable on the partner, the fail banner on
# the partner's screen, partner state after the mission.
#
#   powershell -ExecutionPolicy Bypass -File testing\lab-duo.ps1 [-Mission 16]
#
# Report: testing\reports\duo-<time>\ (report.json, timeline-host.txt, timeline-partner.txt). Exit code = failures.

param(
    [int]$Mission = 16,
    [int]$Port = 16770,
    # -Net: the partner connects through CoopAndreasNetSim (internet-like delay/jitter/loss), the host directly
    # -Pass: end the mission through its own pass routine (autotest passmission) instead of host death
    [switch]$Pass,
    [switch]$Net,
    [int]$Delay = 75,
    [int]$Jitter = 15,
    [double]$Loss = 2,
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)')  # the test copy: never the game someone plays
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')

$report = Join-Path $PSScriptRoot ("reports\duo-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
New-Item -ItemType Directory -Force $report | Out-Null
$script:ReportDir = $report
# the partner runs from a hard-link mirror (testing\make-partner-copy.ps1): two instances from one folder
# crash the 2nd one inside modloader.asi
$PartnerDir = "$GameDir (partner)"
if (-not (Test-Path (Join-Path $PartnerDir 'gta_sa.exe'))) { throw "run testing\make-partner-copy.ps1 first" }
function GameDirOf($who) { if ($who -eq 'partner') { $PartnerDir } else { $GameDir } }

function AutoDir($who) { Join-Path (GameDirOf $who) "CoopAndreas\autotest\$who" }
function Events($who) {
    $p = Join-Path (AutoDir $who) 'events.jsonl'
    if (-not (Test-Path $p)) { return @() }
    @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
}
function Status($who) { try { Get-Content (Join-Path (AutoDir $who) 'status.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null } }
function Cmd($who, $line) {
    for ($i = 0; $i -lt 20; $i++) { try { Add-Content (Join-Path (AutoDir $who) 'commands.txt') $line -Encoding ascii -ErrorAction Stop; return } catch { Start-Sleep -Milliseconds 50 } }
}
function WaitEv($who, [int]$from, [scriptblock]$cond, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do {
        $all = Events $who
        for ($i = $from; $i -lt $all.Count; $i++) { if (& $cond $all[$i]) { return $all[$i] } }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    $null
}
function Count($who) { (Events $who).Count }
function Timeline($who) {
    $all = Events $who; if ($all.Count -eq 0) { return }
    $s = $all[0].t
    $all | ForEach-Object { $rest = ($_.PSObject.Properties | Where-Object { $_.Name -notin 't', 'ev' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '; '{0,7:N1}s  {1,-20} {2}' -f (($_.t - $s) / 1000.0), $_.ev, $rest } |
        Set-Content (Join-Path $report "timeline-$who.txt") -Encoding utf8
}

Get-Process gta_sa, CoopAndreasBot -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
foreach ($w in 'host', 'partner') { New-Item -ItemType Directory -Force (AutoDir $w) | Out-Null; Remove-Item "$(AutoDir $w)\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
$crashDirs = @($LabCrashDir, (Join-Path $PartnerDir 'CoopAndreas_crashes'))
$crashes0 = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count

$work = Join-Path $env:TEMP "coopandreas-duo-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Minimized `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')

$netsim = $null
$partnerPort = $Port
if ($Net) {
    $partnerPort = $Port + 10
    $netsim = Start-Process (Join-Path $LabBin 'CoopAndreasNetSim.exe') -PassThru -WindowStyle Hidden `
        -ArgumentList '--listen', $partnerPort, '--server', "127.0.0.1:$Port", '--delay', $Delay, '--jitter', $Jitter, '--loss', $Loss `
        -RedirectStandardOutput (Join-Path $report 'netsim.log') -RedirectStandardError (Join-Path $report 'netsim.err')
    Write-Host "partner via netsim: ${Delay} ms +-${Jitter} one-way, ${Loss}% loss"
}

function StartGame($who) {
    $dir = GameDirOf $who
    $p = if ($who -eq 'partner') { $partnerPort } else { $Port }
    Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru `
        -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $p -autoname $who -autodir $who"
}

$host_ = $null; $partner = $null
try {
    $host_ = StartGame 'host'
    $e = WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90
    Check 'Host game connects and hosts' ([bool]$e) ''
    if (-not $e) { throw 'host failed' }
    Start-Sleep 15   # let the new-game setup settle before a second game and a mission

    $partner = StartGame 'partner'
    $e = WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90
    Check 'Second real game connects as partner' ([bool]$e) $(if ($e) { "id=$($e.id)" } else { '' })
    if (-not $e) { throw 'partner failed' }
    $h = WaitEv 'host' 0 { param($x) $x.ev -eq 'player_ped_created' } 20
    $p = WaitEv 'partner' 0 { param($x) $x.ev -eq 'player_ped_created' } 20
    Check 'Host sees partner ped, partner sees host ped' ([bool]($h -and $p)) ''
    Start-Sleep 15   # partner's own new-game setup

    $ps = Status 'partner'; $hs = Status 'host'
    Check 'Both games keep running (fps)' ([bool]($ps -and $hs -and $ps.fps -gt 5 -and $hs.fps -gt 5)) "host fps=$($hs.fps) focused=$($hs.focused), partner fps=$($ps.fps) focused=$($ps.focused)"

    # put both at Grove Street
    Cmd 'host' 'teleport 2495 -1680 13.5'; Cmd 'partner' 'teleport 2497 -1680 13.5'
    Start-Sleep 3
    $money0 = (Status 'partner').local.money

    # unported mission: partner should get on-mission, the cutscene, the vote, the banner
    $hf = Count 'host'; $pf = Count 'partner'
    for ($i = 0; $i -lt 15; $i++) {
        Cmd 'host' "startmission $Mission"
        $c = WaitEv 'host' $hf { param($x) $x.ev -eq 'command' -and $x.cmd -eq "startmission $Mission" } 10
        $hf = Count 'host'
        if (-not $c -or $c.result -eq 'ok') { break }
        Start-Sleep 2
    }
    $hf0 = $hf - 3
    $e = WaitEv 'host' 0 { param($x) $x.ev -eq 'mission_script' } 15
    Check "Host starts mission $Mission" ([bool]$e) $(if ($e) { "script=$($e.script) ported=$($e.synced)" } else { '' })
    $e = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_started' } 15
    Check 'Partner gets on-mission' ([bool]$e) ''
    $hc = WaitEv 'host' 0 { param($x) $x.ev -eq 'cutscene_started' } 20
    $pc = WaitEv 'partner' $pf { param($x) $x.ev -eq 'cutscene_started' } 25
    Check 'Cutscene plays on the partner' ([bool]$pc) $(if ($pc) { "host=$($hc.name) partner=$($pc.name)" } else { "host=$($hc.name), partner none" })
    if ($pc) {
        Start-Sleep 2
        Cmd 'partner' 'skipcutscene'
        $v = WaitEv 'host' 0 { param($x) $x.ev -eq 'skip_vote_state' -and $x.votes -ge 1 -and $x.voters -eq 2 } 10
        Check 'Partner vote reaches host (1/2)' ([bool]$v) ''
        Cmd 'host' 'skipcutscene'
        $he = WaitEv 'host' 0 { param($x) $x.ev -eq 'cutscene_ended' } 10
        $pe = WaitEv 'partner' $pf { param($x) $x.ev -eq 'cutscene_ended' } 15
        Check 'Cutscene ends on both after 2/2' ([bool]($he -and $pe)) "host skipped=$($he.skipped) partner=$([bool]$pe)"
    }
    Start-Sleep 4
    if ((Status 'host').cutscene) { Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 4 }
    $hb = (Status 'host').objectiveBlips; $pb = (Status 'partner').objectiveBlips
    Check 'Partner sees the mission objective blips' ($hb -gt 0 -and $pb -ge $hb) "host=$hb partner=$pb"
    if ($Pass) {
        $hm0 = (Status 'host').local.money
        Cmd 'host' 'passmission'
        $t = WaitEv 'host' 0 { param($x) $x.ev -eq 'debug_pass_taken' } 90
        Check 'Mission takes its own pass routine' ([bool]$t) $(if ($t) { "script=$($t.script)" } else { '' })
        $hp = WaitEv 'host' 0 { param($x) $x.ev -eq 'mission_passed' } 30
        $pp = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_passed' } 40
        Check 'Host shows MISSION PASSED' ([bool]$hp) $(if ($hp) { "gxt=$($hp.gxt)" } else { '' })
        Check 'Partner shows MISSION PASSED banner' ([bool]$pp) $(if ($pp) { "gxt=$($pp.gxt)" } else { '' })
        $pend = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_ended' } 45
        Check 'Partner mission flag ends' ([bool]$pend) ''
        Start-Sleep 3
        $ps = Status 'partner'; $hs = Status 'host'
        # some missions reward only respect (M_PASSR); money is shared, so the partner must match the host
        Check 'Partner money matches the host after the reward' ([bool]($ps -and $hs -and $ps.local.money -eq $hs.local.money)) "host $hm0 -> $($hs.local.money), partner $money0 -> $($ps.local.money)"
        Check 'Partner keeps playing after the mission' ([bool]($ps -and -not $ps.onMission -and $partner -and -not $partner.HasExited)) ''
    }
    else {
    Cmd 'host' 'kill'
    $hf = WaitEv 'host' 0 { param($x) $x.ev -eq 'mission_failed' } 60
    $pfail = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_failed' } 60
    Check 'Host shows MISSION FAILED' ([bool]$hf) ''
    Check 'Partner shows MISSION FAILED banner' ([bool]$pfail) ''
    $pend = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_ended' } 45
    Check 'Partner mission flag ends' ([bool]$pend) ''
    Start-Sleep 2   # status.json is rewritten every 500 ms
    $ps = Status 'partner'
    Check 'Partner keeps playing after the mission' ([bool]($ps -and -not $ps.onMission -and $partner -and -not $partner.HasExited)) "money $money0 -> $($ps.local.money), wanted=$($ps.local.wanted)"
    }
}
catch { Check 'Duo run' $false $_.Exception.Message }
finally {
    $new = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($new -le 0) "$new"
    Timeline 'host'; Timeline 'partner'
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    if ($netsim -and -not $netsim.HasExited) { Stop-Process -Id $netsim.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
$LabResults | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $report 'report.json') -Encoding utf8
Write-Host ("{0} passed, {1} failed. Report: {2}" -f ($LabResults.Count - $failed), $failed, $report)
exit $failed
