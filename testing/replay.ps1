# Replays a soak-test actions.txt with two games and the same timing; -Skip removes action numbers (1-based) to
# narrow down a crash.   powershell -File testing\replay.ps1 -Actions <path> [-Skip '3,5-9']
param([string]$Actions, [string]$Skip = "", [int]$Port = 16783, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\replay-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-replay-$Port"
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

$skipSet = @{}
foreach ($part in ($Skip -split ',' | Where-Object { $_ })) { if ($part -match '^(\d+)-(\d+)$') { foreach ($k in [int]$matches[1]..[int]$matches[2]) { $skipSet[$k] = 1 } } else { $skipSet[[int]$part] = 1 } }
$steps = @(Get-Content $Actions | Where-Object { $_ -match '^\d\d:\d\d:\d\d (host|partner) ' })
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    $t0 = $null; $start = Get-Date; $i = 0
    foreach ($line in $steps) {
        $i++
        $parts = $line -split ' ', 3
        $t = [datetime]::ParseExact($parts[0], 'HH:mm:ss', $null)
        if (-not $t0) { $t0 = $t }
        $due = $start.AddSeconds(($t - $t0).TotalSeconds)
        while ((Get-Date) -lt $due) { Start-Sleep -Milliseconds 200 }
        if ($skipSet.ContainsKey($i)) { continue }
        Cmd $parts[1] $parts[2]
        if ($host_.HasExited -or $partner.HasExited) { Write-Host "    crashed after #$i $line"; break }
    }
    Start-Sleep 6
    if ($host_.HasExited -or $partner.HasExited) { Write-Host "    CRASH (host up: $(-not $host_.HasExited), partner up: $(-not $partner.HasExited))" } else { Write-Host '    no crash' }
}
finally {
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    if ($netsim -and -not $netsim.HasExited) { Stop-Process -Id $netsim.Id -Force }
}
