# Soak test: two players (partner through the lag simulator) do random things for -Minutes; any crash, hang
# (hang.txt) or a game that stops answering fails it. Every action is logged to the report's actions.txt.
#   powershell -ExecutionPolicy Bypass -File testing\soak-test.ps1 [-Minutes 20] [-Seed 1]
param([int]$Minutes = 20, [int]$Seed = 1, [int]$Port = 16784, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\soak-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-soak-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
# the partner connects through the lag simulator (internet-like delay, jitter, loss), like a friend on another PC
$partnerPort = $Port + 1
$netsim = Start-Process (Join-Path $LabBin 'CoopAndreasNetSim.exe') -PassThru -WindowStyle Hidden -ArgumentList '--listen', $partnerPort, '--server', "127.0.0.1:$Port", '--delay', 60, '--jitter', 20, '--loss', 1
function StartGame($who) { $dir = GameDirOf $who; $p = if ($who -eq 'partner') { $partnerPort } else { $Port }; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $p -autoname $who -autodir $who" }

$spots = @('2495 -1670 13.5', '1480 -1740 13.5', '2230 -1150 25.8', '1030 -1330 13.5', '-2030 160 28.8', '2030 1010 10.8',
    '1690 -2250 13.5', '370 -1820 7.8', '2500 -1690 13.5', '1960 -2190 13.5')
$cars = @(400, 415, 420, 438, 522, 468, 596, 416, 407, 514, 560, 411)
$missions = @(13, 16, 17, 21, 23, 29, 31, 42, 50, 58, 72)
$rand = New-Object Random $Seed
$actionsLog = Join-Path $report 'actions.txt'
function Act($who, $line) { Add-Content $actionsLog "$(Get-Date -Format HH:mm:ss) $who $line"; Cmd $who $line }
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    $end = (Get-Date).AddMinutes($Minutes); $n = 0
    while ((Get-Date) -lt $end -and -not $host_.HasExited -and -not $partner.HasExited) {
        $n++
        $who = @('host', 'partner')[$rand.Next(2)]
        switch ($rand.Next(12)) {
            0 { $s = $spots[$rand.Next($spots.Count)]; Act 'host' "teleport $s"; Act 'partner' "teleport $s" }
            1 { Act $who "vehicle $($cars[$rand.Next($cars.Count)])"; Act $who 'press cross 3000' }
            2 { Act $who 'leavevehicle' }
            3 { Act $who 'enterpassenger' }
            4 { if (-not (Status 'host').onMission) { Act 'host' "startmission $($missions[$rand.Next($missions.Count)])" } }
            5 { Act 'host' 'skipcutscene'; Act 'partner' 'skipcutscene' }
            6 { Act 'host' 'failmission' }
            7 { Act $who 'kill' }
            8 { Act $who "radio $(1 + $rand.Next(12))" }
            9 { if (-not (Status 'host').onMission) { Act $who "save $(4 + $rand.Next(2))" } }
            10 { Act $who 'nowanted'; Act $who 'heal' }
            11 { Act $who "fire create $((Status $who).local.x + 6) $((Status $who).local.y) $((Status $who).local.z)" }
        }
        Start-Sleep -Milliseconds (1500 + $rand.Next(3000))
        if ($n % 20 -eq 0) {
            $h = Status 'host'; $p = Status 'partner'
            Add-Content $actionsLog ("  -- fps host {0} partner {1}, players {2}/{3}, colModels host {4}/{5} partner {6}/{7}, objects {8}/{9}" -f $h.fps, $p.fps, @($h.players).Count, @($p.players).Count, $h.pools.colModel, $h.pools.colModelSize, $p.pools.colModel, $p.pools.colModelSize, $h.pools.object, $p.pools.object)
        }
    }
    Check "Both games survive $Minutes min of random play ($n actions)" (-not $host_.HasExited -and -not $partner.HasExited) "host up: $(-not $host_.HasExited), partner up: $(-not $partner.HasExited)"
    $h = Status 'host'; $p = Status 'partner'
    Check 'Both games still answer and see each other' ($h -and $p -and $h.fps -gt 5 -and $p.fps -gt 5 -and @($h.players).Count -ge 1 -and @($p.players).Count -ge 1) "fps $($h.fps)/$($p.fps)"
    $hangs = @(Get-ChildItem (AutoDir 'host'), (AutoDir 'partner') -Filter hang.txt -ErrorAction SilentlyContinue)
    Check 'No hangs' ($hangs.Count -eq 0) ($hangs | ForEach-Object { $_.FullName }) 
}
catch { Check 'Soak test runs' $false $_.Exception.Message }
finally {
    $c = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($c -le 0) "$c"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    if ($netsim -and -not $netsim.HasExited) { Stop-Process -Id $netsim.Id -Force }
}
Write-Host "Report: $report"
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
