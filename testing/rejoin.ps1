# A partner whose game quits during a host mission joins again: both see each other, the mission goes on, no crash.
#   powershell -ExecutionPolicy Bypass -File testing\rejoin.ps1 [-Mission 17]
param([int]$Port = 16814, [int]$Mission = 17, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\rejoin-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-rejoin-$Port"
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
    # "/report ..." in the chat writes a playtest report file and is not sent as chat
    $reports = Join-Path $PartnerDir 'CoopAndreas_reports'
    $n0 = @(Get-ChildItem $reports -Filter 'report-*.txt' -ErrorAction SilentlyContinue).Count
    $rr = (CmdResult 'partner' 'chat /report rejoin test report').result; Start-Sleep 2
    $new = @(Get-ChildItem $reports -Filter 'report-*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    $heard = @(Events 'host' | Where-Object { $_.ev -eq 'chat_received' -and $_.text -like '*/report*' }).Count
    $txt = if ($new.Count) { Get-Content $new[-1].FullName -Raw } else { '' }
    Check '/report saves a playtest report (and is not sent as chat)' ($new.Count -gt $n0 -and $txt -match 'rejoin test report' -and $txt -match 'Other players' -and $heard -eq 0) "result $rr, files $n0 -> $($new.Count), host heard it: $heard"
    foreach ($round in 1..2) {
        Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1675 13.5'; Start-Sleep 3
        $s = (CmdResult 'host' "startmission $Mission").result; Start-Sleep 6; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 8
        # the partner's game is closed (crash, alt-F4), the host plays on
        Stop-Process -Id $partner.Id -Force; Start-Sleep 8
        $hpl = @((Status 'host').players); $hp = $hpl.Count
        # a game closed hard sends no goodbye: the session keeps the player until the 30-60 s timeout or their rejoin,
        # but after 5 s of silence the server tells everyone, and the name tag says "(connection lost)"
        Check "Round ${round}: the host keeps playing and shows the partner as connection lost" (-not $host_.HasExited -and ($hp -eq 0 -or $hpl[0].connectionLost)) "host sees $hp player(s), connection lost $(if ($hp) { $hpl[0].connectionLost } else { 'n/a' }), on mission $((Status 'host').onMission)"
        Remove-Item "$(AutoDir 'partner')\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
        $partner = StartGame 'partner'
        $auth = WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90; Start-Sleep 15
        Cmd 'partner' 'teleport 2499 -1675 13.5'; Start-Sleep 5
        $hs = Status 'host'; $ps = Status 'partner'
        $see = @($hs.players).Count -ge 1 -and @($ps.players).Count -ge 1
        Check "Round ${round}: the partner joins again during the mission and both see each other" ($auth -and $see -and -not $host_.HasExited) "joined $([bool]$auth), host sees $(@($hs.players).Count), partner sees $(@($ps.players).Count), host on mission $($hs.onMission), partner on mission $($ps.onMission)"
        Check "Round ${round}: the rejoined partner is in the host's mission too" ($hs.onMission -eq $ps.onMission) "host $($hs.onMission), partner $($ps.onMission) (mission ${Mission}: $s)"
        foreach ($k in 1..6) { if (-not (Status 'host').onMission) { break }; Cmd 'host' 'failmission'; Start-Sleep 3 }
        Start-Sleep 6
    }
}
catch { Check 'Rejoin test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
