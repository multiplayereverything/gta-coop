# Cars driven by another player: how often the partner sees the host's car jump backwards (old snapping vs smoothing).
#   powershell -ExecutionPolicy Bypass -File testing\car-jitter.ps1
param([int]$Port = 16793, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\carjitter-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-carjitter-$Port"
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

function Drive([int]$smooth) {
    # the same run each time: the car stands at the runway's west end facing east, full throttle for 9 s
    # (both players stay on the runway: x 1200 is the sea)
    if (-not (Status 'host').local.inVehicle) {
        Cmd 'host' 'teleport 1450 -2493 13.6'; Start-Sleep 2
        [void](CmdResult 'host' 'vehicle 415'); Start-Sleep 2   # Cheetah
    }
    $r = (CmdResult 'host' 'carto 1450 -2493 13.6 270').result
    Cmd 'partner' 'teleport 1600 -2515 13.6'; Start-Sleep 4
    Cmd 'partner' "smoothing $smooth"   # also resets the metric
    Cmd 'host' 'press cross 9000'
    Start-Sleep 10
    $s = Status 'partner'
    # once the car has rolled to a stop, the partner must see it where the host really is
    Cmd 'host' 'press square 3000'; Start-Sleep 7
    $h = (Status 'host').local; $seen = @((Status 'partner').players) | Where-Object { $_.name -eq 'host' } | Select-Object -First 1
    $off = if ($seen) { [Math]::Sqrt([Math]::Pow($h.x - $seen.x, 2) + [Math]::Pow($h.y - $seen.y, 2)) } else { 999 }
    [pscustomobject]@{ jitter = $s.carJitter; samples = $s.carJitterSamples; snaps = $s.carSnaps; moved = $h.x; offset = $off }
}
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    $old = Drive 0
    $new = Drive 1
    Write-Host ("    old snapping: {0:N1}% back-steps of {1} frames, {6} snaps (host x {2:N0}); smoothing: {3:N1}% of {4}, {7} snaps (host x {5:N0})" -f $old.jitter, $old.samples, $old.moved, $new.jitter, $new.samples, $new.moved, $old.snaps, $new.snaps)
    Check "The host's car moves smoothly on the partner's screen" ($new.samples -gt 50 -and $new.jitter -le [Math]::Max(1.0, $old.jitter / 3)) ("back-steps {0:N1}% -> {1:N1}%" -f $old.jitter, $new.jitter)
    Check "After stopping, the partner sees the host's car where it really is" ($new.offset -lt 2.0) ("{0:N2} m off (old snapping {1:N2} m)" -f $new.offset, $old.offset)

    # trailer: the host's tanker tows a trailer; the partner sees it hooked on, also after driving
    Cmd 'host' 'leavevehicle'; Start-Sleep 1
    Cmd 'host' 'teleport 1450 -2470 13.6'; Start-Sleep 2
    [void](CmdResult 'host' 'vehicle 514'); Start-Sleep 2   # Tanker
    [void](CmdResult 'host' 'carto 1450 -2470 13.6 270'); Start-Sleep 1
    $tr = (CmdResult 'host' 'trailer 584').result   # petrol trailer
    Cmd 'partner' 'teleport 1520 -2515 13.6'; Start-Sleep 4
    $ht0 = (Status 'host').towing; $pt0 = (Status 'partner').towing
    Cmd 'host' 'press cross 6000'; Start-Sleep 8
    $ht1 = (Status 'host').towing; $pt1 = (Status 'partner').towing; $hx = (Status 'host').local.x
    Check "A trailer the host tows is hooked on for the partner too" ($ht0 -ge 1 -and $pt0 -ge 1 -and $ht1 -ge 1 -and $pt1 -ge 1 -and $hx -gt 1470) "towing host/partner $ht0/$pt0, after driving to x $([int]$hx): $ht1/$pt1 ($tr)"
}
catch { Check 'Car jitter test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    if ($netsim -and -not $netsim.HasExited) { Stop-Process -Id $netsim.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
