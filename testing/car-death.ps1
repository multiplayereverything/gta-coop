# A partner who dies inside a car (driver or passenger) and respawns: no crash on either game.
#   powershell -ExecutionPolicy Bypass -File testing\car-death.ps1
param([int]$Port = 16800, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\car-death-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-cardeath-$Port"
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
    $cases = @(
        @{ n = 'driver, no mission'; mission = 0; seat = 'driver' },
        @{ n = 'driver, mission 21'; mission = 21; seat = 'driver' },
        @{ n = 'passenger of the host, no mission'; mission = 0; seat = 'passenger' }
    )
    foreach ($c in $cases) {
        Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1675 13.5'; Start-Sleep 4
        if ($c.mission) { [void](CmdResult 'host' "startmission $($c.mission)"); Start-Sleep 3; [void](Wait-Playable { Status 'partner' } 40) }
        if ($c.seat -eq 'driver') { Cmd 'partner' 'vehicle 514'; Cmd 'partner' 'press cross 3000' }
        else { Cmd 'host' 'vehicle 420'; Cmd 'host' 'press cross 3000'; Start-Sleep 3; Cmd 'partner' 'enterpassenger' }
        Start-Sleep 5
        $inCar = (Status 'partner').local.inVehicle
        $pf = Count 'partner'; [void](CmdResult 'partner' 'kill')
        [void](WaitEv 'partner' $pf { param($x) $x.ev -eq 'alive' } 60)
        Start-Sleep 2
        # what the soak did next: the host gets a new car right away
        Cmd 'host' 'leavevehicle'; Start-Sleep 1; Cmd 'host' 'vehicle 420'; Cmd 'host' 'press cross 3000'
        Start-Sleep 12
        foreach ($t in 1..6) { if (-not (Status 'host').onMission) { break }; Cmd 'host' 'failmission'; Start-Sleep 3 }
        [void](Wait-Playable { Status 'partner' } 60)
        $up = -not $host_.HasExited -and -not $partner.HasExited
        Check "The partner dies in a car ($($c.n)) and respawns: both games keep running" $up "partner was in a car: $inCar; host up $(-not $host_.HasExited), partner up $(-not $partner.HasExited)"
        if (-not $up) { break }
        Cmd 'host' 'leavevehicle'; Cmd 'partner' 'leavevehicle'; Start-Sleep 2
    }
}
catch { Check 'Car death test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
