# A partner takes a vehicle the host spawned (like a mission bike or car) and rides away: the partner keeps it, both
# screens agree where it is.   powershell -ExecutionPolicy Bypass -File testing\vehicle-takeover.ps1
param([int]$Port = 16816, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\vehicle-takeover-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-takeover-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

function Dist2($a, $b) { if ($null -eq $a -or $null -eq $b) { return 9999 }; [math]::Sqrt(($a.x - $b.x) * ($a.x - $b.x) + ($a.y - $b.y) * ($a.y - $b.y)) }
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    foreach ($v in @(@{ n = 'BMX (mission)'; m = 481 }, @{ n = 'car (mission)'; m = 404 })) {
        Cmd 'host' 'teleport 2440 -1665 13.4'; Cmd 'partner' 'teleport 2446 -1672 13.4'; Start-Sleep 3
        Cmd 'host' 'face 2540 -1665 13.4'; [void](CmdResult 'host' "vehicle $($v.m) mission"); Start-Sleep 2; Cmd 'host' 'leavevehicle'; Start-Sleep 3
        # the partner gets in the host's vehicle and rides off east along Grove Street
        $r = (CmdResult 'partner' 'entermissioncar').result; Start-Sleep 4
        $p0 = (Status 'partner').local
        Cmd 'partner' 'press cross 6000'; Start-Sleep 8
        $p1 = (Status 'partner').local
        $onHost = @((Status 'host').players)[0]
        $moved = Dist2 $p0 $p1; $agree = Dist2 $p1 $onHost
        $flips = @(Events 'partner' | Where-Object { $_.ev -eq 'vehicle_exited' }).Count
        Check "The partner takes the host's $($v.n) and rides away" ($p1.inVehicle -and $moved -gt 10) ("enter: {0}; in vehicle {1}, moved {2:N0} m" -f $r, $p1.inVehicle, $moved)
        Check "... and the host sees the partner where the partner is" ($agree -lt 6) ("{0:N1} m apart" -f $agree)
        # moved in one go while in it (the playthrough's catch-up): it must stay there, not be pulled back
        if (-not (Status 'partner').local.inVehicle) { [void](CmdResult 'partner' 'entermissioncar'); Start-Sleep 4 }
        $before = (Status 'partner').local
        Cmd 'partner' ("teleport {0:F1} {1:F1} {2:F1}" -f ($before.x + 60), $before.y, ($before.z + 1)); Start-Sleep 5
        $after = (Status 'partner').local
        $exits = @(Events 'partner' | Where-Object { $_.ev -eq 'vehicle_exited' }).Count
        Check "... moved 60 m while in it, the partner stays there in the vehicle" ($after.inVehicle -and (Dist2 $before $after) -gt 50) ("in vehicle {0}, moved {1:N0} m (exits so far {2})" -f $after.inVehicle, (Dist2 $before $after), $exits)
        Cmd 'partner' 'leavevehicle'; Start-Sleep 2
    }
}
catch { Check 'Vehicle takeover test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
