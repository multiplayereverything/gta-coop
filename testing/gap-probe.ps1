# Host-run missions with two real games: what the partner sees compared with the host (map blips, 3D "go here"
# markers, race checkpoints) and who gets the money when the mission passes. Test copies only.
#   powershell -ExecutionPolicy Bypass -File testinggap-probe.ps1 [-Missions "16,17"]
param([string]$Missions = "13,16,17,18,21,22,23,29,35,55", [int]$Port = 16796, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\gap-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-gap-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

function Snap($who) {
    $s = Status $who
    if (-not $s) { return $null }
    [pscustomobject]@{ blips = @($s.blips).Count; markers = @($s.markers | Where-Object { $_.type -eq 1 }).Count; checkpoints = @($s.checkpoints).Count
        money = $s.local.money; onMission = $s.onMission; text = $s.mission; fires = $s.missionFires; pickups = $s.missionPickups }
}
$rows = @()
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    foreach ($id in $Missions.Split(',')) {
        if ($host_.HasExited -or $partner.HasExited) { $rows += [pscustomobject]@{ id = $id; note = 'game gone' }; break }
        Cmd 'host' 'nowanted'; Cmd 'partner' 'nowanted'
        Cmd 'host' 'interior 0'; Cmd 'partner' 'interior 0'
        Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1670 13.5'; Start-Sleep 4
        $hf = Count 'host'
        $r = CmdResult 'host' "startmission $id" 10
        if (-not (WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_started' } 20)) { $rows += [pscustomobject]@{ id = $id; note = "no start ($($r.result))" }; EndMission; continue }
        $shownBlips = $false
        $max = @{ hb = 0; pb = 0; hm = 0; pm = 0; hc = 0; pc = 0; hf = 0; pf = 0; hp = 0; pp = 0 }
        for ($t = 0; $t -lt 22; $t++) {
            Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 2
            $h = Snap 'host'; $p = Snap 'partner'
            if ($h -and $p -and -not (Status 'host').cutscene) {
                $max.hb = [Math]::Max($max.hb, $h.blips); $max.pb = [Math]::Max($max.pb, $p.blips)
                $max.hm = [Math]::Max($max.hm, $h.markers); $max.pm = [Math]::Max($max.pm, $p.markers)
                $max.hc = [Math]::Max($max.hc, $h.checkpoints); $max.pc = [Math]::Max($max.pc, $p.checkpoints)
                $max.hf = [Math]::Max($max.hf, $h.fires); $max.pf = [Math]::Max($max.pf, $p.fires); $max.hp = [Math]::Max($max.hp, $h.pickups); $max.pp = [Math]::Max($max.pp, $p.pickups)
                if ($h.blips -ne $p.blips -and -not $shownBlips) {
                    $shownBlips = $true
                    Write-Host ("    host blips: " + ((Status 'host').blips | ConvertTo-Json -Compress) + "  partner blips: " + ((Status 'partner').blips | ConvertTo-Json -Compress))
                }
            }
        }
        $hm0 = (Snap 'host').money; $pm0 = (Snap 'partner').money
        Cmd 'host' 'passmission'
        $deadline = (Get-Date).AddSeconds(45); while ((Status 'host').onMission -and (Get-Date) -lt $deadline) { Start-Sleep 2; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene' }
        Start-Sleep 4
        $passed = -not (Status 'host').onMission
        $hd = (Snap 'host').money - $hm0; $pd = (Snap 'partner').money - $pm0
        $row = [pscustomobject]@{ id = $id; mission = (Events 'host' | Where-Object { $_.ev -eq 'mission_started' } | Select-Object -Last 1).script
            blips = "$($max.hb)/$($max.pb)"; markers = "$($max.hm)/$($max.pm)"; checkpoints = "$($max.hc)/$($max.pc)"
            passed = $passed; money = "$hd/$pd"; fires = "$($max.hf)/$($max.pf)"; pickups = "$($max.hp)/$($max.pp)"; note = '' }
        $rows += $row
        Write-Host ("  {0,-3} {1,-9} blips h/p {2,-6} markers {3,-6} checkpoints {4,-6} fires {7,-6} pickups {8,-6} passed {5,-5} money h/p {6}" -f $row.id, $row.mission, $row.blips, $row.markers, $row.checkpoints, $row.passed, $row.money, $row.fires, $row.pickups)
        EndMission; Start-Sleep 5
    }
}
catch { Check 'Gap probe runs' $false $_.Exception.Message }
finally {
    $new = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($new -le 0) "$new"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$rows | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $report 'gaps.json') -Encoding utf8
Write-Host "Report: $report"
