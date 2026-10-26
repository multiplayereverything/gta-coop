# A player who dies while a mission cutscene plays (fire, shot by a synced NPC) must not crash their game; the host
# starting a mission while a partner is still dead neither crashes nor fails it at once.
#   powershell -ExecutionPolicy Bypass -File testing\cutscene-death.ps1 [-Mission 17] [-Who partner] [-Rounds 3]
param([int]$Port = 16794, [int]$Mission = 17, [string]$Who = "partner", [int]$Rounds = 3, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\cutscene-death-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-csdeath-$Port"
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
    foreach ($round in @(1..3 | Where-Object { $_ -le $Rounds })) {
        $f = Count $Who
        Write-Host "    round ${round}: $((CmdResult 'host' "startmission $Mission").result)"
        $cs = WaitEv $Who $f { param($x) $x.ev -eq 'cutscene_started' } 30
        Start-Sleep -Milliseconds (500 + 1500 * $round)
        if ($round -eq 1 -and $cs) {
            $l = (Status $Who).local; [void](CmdResult $Who "fire create $($l.x) $($l.y) $($l.z)"); Start-Sleep 5
            $h = (Status $Who).local.health
            Check "A fire under the $Who during the cutscene does not hurt them (no control, like single player)" ($h -ge 99) "health $h"
            [void](CmdResult $Who 'kill'); Start-Sleep 2
            $h = (Status $Who).local.health
            Check "A deadly hit on the $Who during the cutscene does not kill them" ($h -ge 99) "health $h"
        }
        # a death the protection can't stop (e.g. already dying when the cutscene starts): only zero the health
        [void](CmdResult $Who 'kill hard')
        Start-Sleep 20
        $up = -not $host_.HasExited -and -not $partner.HasExited
        Check "Round ${round}: the $Who dies during the opening cutscene of mission $Mission, both games keep running" ($up -and $cs) "cutscene $(if ($cs) { $cs.name } else { 'not seen' }), host up $(-not $host_.HasExited), partner up $(-not $partner.HasExited)"
        if (-not $up) { break }
        EndMission; Start-Sleep 8
    }
    $s = Status $Who
    Check "The $Who is back in play afterwards" ($s -and $s.local.health -gt 0) "health $($s.local.health)"

    # the host starts a mission while the partner still lies dead from before: no crash, no instant fail;
    # the partner dying during the mission still fails it
    EndMission; Start-Sleep 5
    $pf = Count 'partner'; [void](CmdResult 'partner' 'kill'); Start-Sleep 3
    $f = Count 'host'
    $r = (CmdResult 'host' "startmission $Mission").result
    Start-Sleep 8
    $failed = WaitEv 'host' $f { param($x) $x.ev -eq 'mission_failed' } 1
    Check 'The host starts a mission while the partner is still dead: no crash, the mission goes on' (-not $host_.HasExited -and $r -eq 'ok' -and -not $failed -and (Status 'host').onMission) "start $r, failed $([bool]$failed), host up $(-not $host_.HasExited)"
    $a = WaitEv 'partner' $pf { param($x) $x.ev -eq 'alive' } 60
    [void](Wait-Playable { Status 'partner' } 60); $f = Count 'host'
    [void](CmdResult 'partner' 'kill')
    $failed = WaitEv 'host' $f { param($x) $x.ev -eq 'mission_failed' } 20
    Check 'The partner dying during that mission still fails it' ($failed -and -not $host_.HasExited) "failed $([bool]$failed)"
}
catch { Check 'Cutscene death test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
