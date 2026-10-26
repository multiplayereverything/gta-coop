# Collectibles (oysters, horseshoes) with two players: one player collects, it counts for the shared story (host) and
# disappears for everyone.   powershell -ExecutionPolicy Bypass -File testing\collectibles.ps1 [-Collector partner]
param([int]$Port = 16810, [string]$Collector = "partner", [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\collectibles-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-collect-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

function Col($who) { (Status $who).collectibles }
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    $other = if ($Collector -eq 'host') { 'partner' } else { 'host' }
    $h0 = Col 'host'; $p0 = Col 'partner'
    Write-Host "    start host: $($h0 | ConvertTo-Json -Compress)"
    Write-Host "    start partner: $($p0 | ConvertTo-Json -Compress)"
    foreach ($kind in @(@{ n = 'oyster'; model = 953; stat = 'oysters' }, @{ n = 'horseshoe'; model = 954; stat = 'horseshoes' })) {
        Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1675 13.5'; Start-Sleep 3
        $near = (CmdResult $Collector "nearpickup $($kind.model)").result
        if (-not $near -or $near -eq 'none') { Check "A $($kind.n) exists in the world" $false "nearpickup: $near"; continue }
        $xyz = ($near -split ' ')[0..2] -join ' '
        $b = @{ c = (Col $Collector); o = (Col $other) }
        # both stand there (the other player's game streams the area); the collector walks onto it
        Cmd $other "teleport $(([double]($near -split ' ')[0] + 6)) $(($near -split ' ')[1]) $(($near -split ' ')[2])"
        Cmd $Collector "teleport $xyz"; Start-Sleep 8
        $a = @{ c = (Col $Collector); o = (Col $other) }
        $key = "pickups$($kind.model)"
        Write-Host ("    {0}: collector {1}->{2} (left {3}->{4}), other {5}->{6} (left {7}->{8})" -f $kind.n, $b.c.($kind.stat), $a.c.($kind.stat), $b.c.$key, $a.c.$key, $b.o.($kind.stat), $a.o.($kind.stat), $b.o.$key, $a.o.$key)
        Check "The $Collector collects a $($kind.n): it counts on their game" ($a.c.($kind.stat) -eq $b.c.($kind.stat) + 1) "$($b.c.($kind.stat)) -> $($a.c.($kind.stat))"
        Check "... it counts on the $other's game too (shared story progress)" ($a.o.($kind.stat) -eq $b.o.($kind.stat) + 1) "$($b.o.($kind.stat)) -> $($a.o.($kind.stat))"
        Check "... and it is gone from the $other's world" ($a.o.$key -eq $b.o.$key - 1) "left $($b.o.$key) -> $($a.o.$key)"
    }
}
catch { Check 'Collectibles test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
