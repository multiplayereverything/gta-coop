# Co-op over a bad network: the partner connects through the coop-anything chaos relay (toolkit-coop-anything/tools/chaos)
#   powershell -ExecutionPolicy Bypass -File testing\chaos-test.ps1 [-Profiles 'good_wifi,bad_wifi,mobile_tether,hell'] [-Seed N]
param([int]$Port = 16804, [string]$Profiles = 'good_wifi,bad_wifi,mobile_tether,hell', [int]$Seed = 0, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\chaos-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-chaos-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $(if ($who -eq 'partner') { $script:RelayPort } else { $Port }) -autoname $who -autodir $who" }

$ChaosPy = Join-Path (Split-Path -Parent $PSScriptRoot) 'toolkit-coop-anything\tools\chaos\chaos.py'
$info = Join-Path $report 'chaos-info.json'
# Start-Process does not quote list arguments in PowerShell 5.1: paths with spaces must carry their own quotes
$relayArgs = @('-3', '-I', "`"$ChaosPy`"", 'relay', '--target', "127.0.0.1:$Port", '--profile', 'lan', '--info-file', "`"$info`"", '--log', "`"$(Join-Path $report 'chaos.jsonl')`"")
if ($Seed) { $relayArgs += @('--seed', $Seed) }
$relay = Start-Process py -ArgumentList $relayArgs -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $report 'chaos.err')
$deadline = (Get-Date).AddSeconds(15); while (-not (Test-Path $info) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
if (-not (Test-Path $info)) { Check 'Chaos relay starts' $false (Get-Content (Join-Path $report 'chaos.err') -Raw); if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }; exit 1 }
$ri = Get-Content $info -Raw | ConvertFrom-Json; $script:RelayPort = $ri.listen; $rpc = $ri.rpc
function Chaos($method, $json = '{}') { & py -3 -I $ChaosPy call --rpc-port $rpc $method ($json -replace '"', '\"') }
function Dist($a, $b) { if ($null -eq $a -or $null -eq $b) { return 9999 }; [math]::Sqrt(($a.x - $b.x) * ($a.x - $b.x) + ($a.y - $b.y) * ($a.y - $b.y)) }
function HostSeesPartner { Dist @((Status 'host').players)[0] (Status 'partner').local }
function PartnerSeesHost { Dist @((Status 'partner').players)[0] (Status 'host').local }
function WaitClose([scriptblock]$d, [double]$max, [int]$seconds) { $t0 = Get-Date; do { $v = & $d; if ($v -le $max) { return $v }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $t0).TotalSeconds -lt $seconds); & $d }
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed to join through the relay' }
    Start-Sleep 15
    $spots = @('2495 -1670 13.5', '2470 -1660 13.4', '2510 -1690 13.5')
    foreach ($prof in ($Profiles -split ',')) {
        [void](Chaos 'set_profile' "{`"profile`":`"$prof`"}"); [void](Chaos 'reset_stats')
        # on foot: each sees the other where they are
        Cmd 'host' "teleport $($spots[0])"; Cmd 'partner' "teleport $($spots[1])"; Start-Sleep 2
        $a = WaitClose { HostSeesPartner } 3 20; $b = WaitClose { PartnerSeesHost } 3 20
        Check "[$prof] each player sees the other in the right place" ($a -le 3 -and $b -le 3) ("host sees partner {0:N1} m off, partner sees host {1:N1} m off" -f $a, $b)
        # in a car: the partner sees the host's car arrive where it stops
        Cmd 'host' 'vehicle 420'; Start-Sleep 3; Cmd 'host' "carto $($spots[2]) 0"; Cmd 'host' 'press cross 4000'; Start-Sleep 14; Cmd 'host' 'leavevehicle'
        $c = WaitClose { PartnerSeesHost } 4 20
        Check "[$prof] after the host moves and drives the car the partner sees the host where the host is" ($c -le 4) ("{0:N1} m off" -f $c)
        # story: a mission with a cutscene reaches the partner, and its end too
        $pf = Count 'partner'
        $r = (CmdResult 'host' 'startmission 17').result
        $ms = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_started' } 25
        $cs = WaitEv 'partner' $pf { param($x) $x.ev -eq 'cutscene_started' } 25
        Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 5
        foreach ($t in 1..6) { if (-not (Status 'host').onMission) { break }; Cmd 'host' 'failmission'; Start-Sleep 3 }
        $me = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_ended' } 25
        Check "[$prof] a host mission (start, cutscene, end) reaches the partner" ($r -eq 'ok' -and $ms -and $cs -and $me) "start $r, partner: started $([bool]$ms), cutscene $([bool]$cs), ended $([bool]$me)"
        $st = Chaos 'stats'
        Add-Content (Join-Path $report 'chaos-stats.txt') "$prof $st"
        Write-Host "    [$prof] relay: $(($st | Out-String).Trim() -replace '\s+', ' ')".Substring(0, [Math]::Min(220, 14 + ($st | Out-String).Length))
        $up = -not $host_.HasExited -and -not $partner.HasExited
        Check "[$prof] both games keep running and connected" ($up -and (Status 'partner').authenticated -and @((Status 'host').players).Count -ge 1) "host up $(-not $host_.HasExited), partner up $(-not $partner.HasExited)"
        if (-not $up) { break }
        Start-Sleep 5
    }
    # outages on a normal link: host-to-partner silence for 4 s, then everything down for 10 s
    [void](Chaos 'set_profile' '{"profile":"good_wifi"}')
    [void](Chaos 'partition' '{"dir":"s2c","on":true,"duration_ms":4000}'); Start-Sleep 6
    Cmd 'host' "teleport $($spots[1])"; Cmd 'partner' "teleport $($spots[0])"; Start-Sleep 2
    $a = WaitClose { HostSeesPartner } 3 20; $b = WaitClose { PartnerSeesHost } 3 20
    Check 'After 4 s of one-way silence both are back in sync' ($a -le 3 -and $b -le 3 -and (Status 'partner').authenticated) ("{0:N1} / {1:N1} m off" -f $a, $b)
    [void](Chaos 'disconnect' '{"duration_ms":10000}'); Start-Sleep 13
    Cmd 'host' "teleport $($spots[0])"; Cmd 'partner' "teleport $($spots[1])"; Start-Sleep 2
    $a = WaitClose { HostSeesPartner } 3 30; $b = WaitClose { PartnerSeesHost } 3 30
    $ps = Status 'partner'
    Check 'After a 10 s full outage the session continues (or the partner is told and rejoins)' ($a -le 3 -and $b -le 3) ("{0:N1} / {1:N1} m off, partner connected {2} authenticated {3}, host sees {4} player(s)" -f $a, $b, $ps.connected, $ps.authenticated, @((Status 'host').players).Count)
}
catch { Check 'Chaos test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if ($relay -and -not $relay.HasExited) { try { [void](Chaos 'shutdown') } catch {}; Start-Sleep 1; if (-not $relay.HasExited) { Stop-Process -Id $relay.Id -Force } }; if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
