# Runs the mission sweep twice in parallel to halve the time: one game from the normal install, one from the
# partner copy (testing\make-partner-copy.ps1; modloader off, so the two instances coexist), each with its own
# server port, bots and autotest folder. Missions are split alternately between the two.
#
#   powershell -ExecutionPolicy Bypass -File testing\mission-sweep-parallel.ps1 -Missions "11-112"
#
# Then run testing\mission-catalog.ps1 (it merges every sweep report, newest result per mission wins).

param([string]$Missions = '11-112', [string]$EndBy = 'fail')

$ids = @($Missions -split ',' | Where-Object { $_.Trim() } | ForEach-Object {
    $p = $_.Trim() -split '-'
    if ($p.Count -eq 2) { [int]$p[0]..[int]$p[1] } else { [int]$p[0] }
})
$a = @(); $b = @()
for ($i = 0; $i -lt $ids.Count; $i++) { if ($i % 2 -eq 0) { $a += $ids[$i] } else { $b += $ids[$i] } }

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$game = Join-Path $root 'GTA San Andreas'
$partner = "$game (partner)"
if (-not (Test-Path (Join-Path $partner 'gta_sa.exe'))) { throw 'run testing\make-partner-copy.ps1 first' }

Get-Process gta_sa, CoopAndreasBot -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*coopandreas-sweep*' } | Stop-Process -Force

$sweep = Join-Path $PSScriptRoot 'mission-sweep.ps1'
$logA = Join-Path $env:TEMP 'sweep-A.log'; $logB = Join-Path $env:TEMP 'sweep-B.log'
$pa = Start-Process powershell -PassThru -WindowStyle Hidden -RedirectStandardOutput $logA -ArgumentList `
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$sweep`"", '-Missions', ($a -join ','), '-Port', '16769', '-EndBy', $EndBy, '-GameDir', "`"$game`""
Start-Sleep 20   # stagger the boots
$pb = Start-Process powershell -PassThru -WindowStyle Hidden -RedirectStandardOutput $logB -ArgumentList `
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$sweep`"", '-Missions', ($b -join ','), '-Port', '16771', '-EndBy', $EndBy, '-GameDir', "`"$partner`""

Write-Host "sweep A: $($a.Count) missions (log $logA), sweep B: $($b.Count) missions (log $logB)"
$pa.WaitForExit(); $pb.WaitForExit()
Get-Content $logA, $logB | Where-Object { $_ -like 'Sweep done*' }
