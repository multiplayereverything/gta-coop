# Which actions use up the game's collision-model pool (it filled up after ~10 min of soak play and crashed).
#   powershell -ExecutionPolicy Bypass -File testing\pool-probe.ps1 [-Repeat 3]
param([int]$Port = 16802, [int]$Repeat = 3, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\pool-probe-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-poolprobe-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

function Pools { $h = Status 'host'; $p = Status 'partner'; @{ h = $h.pools.colModel; p = $p.pools.colModel; hb = $h.pools.building; pb = $p.pools.building } }
function Measure-Step([string]$name, [scriptblock]$action) {
    $a = Pools
    for ($r = 0; $r -lt $Repeat; $r++) { & $action }
    Start-Sleep 4
    $b = Pools
    Write-Host ("    {0,-34} colModel host {1} -> {2} ({3:+0;-0;0})  partner {4} -> {5} ({6:+0;-0;0})" -f $name, $a.h, $b.h, ($b.h - $a.h), $a.p, $b.p, ($b.p - $a.p))
    $script:steps += [pscustomobject]@{ step = $name; host = $b.h - $a.h; partner = $b.p - $a.p }
}
$script:steps = @()
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    function Both($line) { Cmd 'host' $line; Cmd 'partner' $line }
    Both 'teleport 2495 -1670 13.5'; Start-Sleep 6
    $p0 = Pools; Write-Host "    start: host $($p0.h) partner $($p0.p)"
    Measure-Step 'teleport round trip LS-SF-LV-LS' { Both 'teleport -2030 160 28.8'; Start-Sleep 6; Both 'teleport 2030 1010 10.8'; Start-Sleep 6; Both 'teleport 2495 -1670 13.5'; Start-Sleep 6 }
    Measure-Step 'host car spawn + leave' { Cmd 'host' 'vehicle 420'; Start-Sleep 3; Cmd 'host' 'leavevehicle'; Start-Sleep 2 }
    Measure-Step 'partner car spawn + leave' { Cmd 'partner' 'vehicle 514'; Start-Sleep 3; Cmd 'partner' 'leavevehicle'; Start-Sleep 2 }
    Measure-Step 'partner rides with host' { Cmd 'host' 'vehicle 420'; Start-Sleep 3; Cmd 'partner' 'enterpassenger'; Start-Sleep 5; Cmd 'partner' 'leavevehicle'; Cmd 'host' 'leavevehicle'; Start-Sleep 2 }
    Measure-Step 'fire near players' { $l = (Status 'host').local; Cmd 'host' "fire create $($l.x + 6) $($l.y) $($l.z)"; Start-Sleep 4 }
    Measure-Step 'partner dies + respawns' { $pf = Count 'partner'; Cmd 'partner' 'kill'; [void](WaitEv 'partner' $pf { param($x) $x.ev -eq 'alive' } 60); [void](Wait-Playable { Status 'partner' } 60); Both 'teleport 2495 -1670 13.5'; Start-Sleep 3 }
    Measure-Step 'host dies + respawns' { $hf = Count 'host'; Cmd 'host' 'kill'; [void](WaitEv 'host' $hf { param($x) $x.ev -eq 'alive' } 60); [void](Wait-Playable { Status 'host' } 60); Both 'teleport 2495 -1670 13.5'; Start-Sleep 3 }
    Measure-Step 'mission 21 start + fail' { [void](CmdResult 'host' 'startmission 21'); Start-Sleep 8; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 3; foreach ($t in 1..6) { if (-not (Status 'host').onMission) { break }; Cmd 'host' 'failmission'; Start-Sleep 3 }; Both 'teleport 2495 -1670 13.5'; Start-Sleep 4 }
    Measure-Step 'mission 17 start + fail' { [void](CmdResult 'host' 'startmission 17'); Start-Sleep 8; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 3; foreach ($t in 1..6) { if (-not (Status 'host').onMission) { break }; Cmd 'host' 'failmission'; Start-Sleep 3 }; Both 'teleport 2495 -1670 13.5'; Start-Sleep 4 }
    Measure-Step 'shared save' { Cmd 'host' 'save 5'; Start-Sleep 5 }
    Measure-Step 'idle 20 s' { Start-Sleep 20 }
    $p1 = Pools; Write-Host "    end: host $($p1.h) partner $($p1.p)"
    $script:steps | ConvertTo-Json | Set-Content (Join-Path $report 'steps.json') -Encoding utf8
    Check 'Pool probe ran' $true "colModel host $($p0.h) -> $($p1.h), partner $($p0.p) -> $($p1.p)"
}
catch { Check 'Pool probe runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
