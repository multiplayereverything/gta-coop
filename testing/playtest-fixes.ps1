# Checks the fixes for the 2026-10-27 playtest reports, with two test games:
# chat commands (/tp, /bring, /mission), a partner starting a mission from its marker and by request, tag spraying
# shared through the spray sender, one visible barber when both walk in together, and the hospital tip that used
# to lock players after a respawn.
#   powershell -ExecutionPolicy Bypass -File testing\playtest-fixes.ps1
param([int]$Port = 16797, [string[]]$Parts = @("chat", "marker", "request", "tags", "barber", "hospital"), [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\playtest-fixes-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
function Pos($who) { $s = Status $who; if ($s) { $s.local } }
function Dist($a, $b) { if (-not $a -or -not $b) { return 9999 }; [math]::Sqrt([math]::Pow($a.x - $b.x, 2) + [math]::Pow($a.y - $b.y, 2)) }
function EndMission { foreach ($t in 1..10) { if (-not (Status 'host').onMission) { return $true }; Cmd 'host' 'failmission'; Start-Sleep 3 }; -not (Status 'host').onMission }
function WaitFor([scriptblock]$cond, [int]$seconds) { $deadline = (Get-Date).AddSeconds($seconds); do { if (& $cond) { return $true }; Start-Sleep -Milliseconds 500 } while ((Get-Date) -lt $deadline); $false }

# only this test's own game copies: never the game someone is playing
Get-Process gta_sa -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$GameDir*" -or $_.Path -like "$PartnerDir*" } | Stop-Process -Force
Start-Sleep 1
foreach ($w in 'host', 'partner') { New-Item -ItemType Directory -Force (AutoDir $w) | Out-Null; Remove-Item "$(AutoDir $w)\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
$crashDirs = @($LabCrashDir, (Join-Path $PartnerDir 'CoopAndreas_crashes'))
$crashes0 = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count
$work = Join-Path $env:TEMP "coopandreas-playtestfixes-$Port"
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
    foreach ($g in $host_, $partner) { Write-Host "    game: $($g.Path)" }
    [void](Wait-Playable { Status 'host' } 40); [void](Wait-Playable { Status 'partner' } 40)

    if ($Parts -contains "chat") {
    # --- chat commands -----------------------------------------------------------------------------------------------
    Cmd 'host' 'teleport 2495 -1660 13.5'; Cmd 'partner' 'teleport 2300 -1655 14.0'; Start-Sleep 4
    [void](CmdResult 'partner' 'chat /tp host'); Start-Sleep 3
    $d = Dist (Pos 'host') (Pos 'partner')
    Check '/tp host brings the partner next to the host' ($d -lt 6) ("{0:F1} m apart" -f $d)

    Cmd 'host' 'teleport 2400 -1650 13.6'; Start-Sleep 3
    [void](CmdResult 'host' 'chat /bring partner'); Start-Sleep 4
    $d = Dist (Pos 'host') (Pos 'partner')
    Check '/bring partner moves the partner to the host' ($d -lt 6) ("{0:F1} m apart" -f $d)

    $hello = CmdResult 'partner' 'chat hello everyone'
    Check 'An ordinary chat line still goes out as chat' ($hello -and $hello.result -ne 'command') "result=$($hello.result)"
    }

    # (before the missions: failing Big Smoke re-locks the shops on the host's game, as in single player)
    if ($Parts -contains "barber") {
    # --- barber: both walk in together, each sees one barber ---------------------------------------------------------
    Cmd 'host' 'enex BARBERS 1'; Cmd 'partner' 'enex BARBERS 1'
    Cmd 'host' 'teleport 2073.0 -1795.5 13.6'; Cmd 'partner' 'teleport 2074.0 -1796.5 13.6'; Start-Sleep 3
    $door = @((Status 'host').doors) | Where-Object { $_.name -eq 'BARBERS' -and $_.z -lt 500 } | Select-Object -First 1
    if ($door) {
        # the partner first, the host 2 s later: the partner's shop script waits 2 s for an existing barber and then
        # makes its own, while the host's looks once on arrival - both made one (the reported two barbers)
        Cmd 'partner' ("teleport {0} {1} {2}" -f $door.x, $door.y, ($door.z + 0.6)); Start-Sleep 2
        Cmd 'host' ("teleport {0} {1} {2}" -f $door.x, $door.y, ($door.z + 0.6))
        Start-Sleep 14
        # a door entry the game missed (the test puts players on the trigger instead of walking in): once more
        foreach ($who in 'partner', 'host') {
            if ((Status $who).area -eq 0) {
                Write-Host "    $who still outside, through the door again"
                Cmd $who ("teleport {0} {1} {2}" -f ($door.x + 3), $door.y, ($door.z + 0.6)); Start-Sleep 2
                Cmd $who ("teleport {0} {1} {2}" -f $door.x, $door.y, ($door.z + 0.6)); Start-Sleep 10
            }
        }
        $seen = @{}
        foreach ($who in 'host', 'partner') {
            $total = 0; $visible = 0
            foreach ($m in 156, 176, 177) {
                $r = CmdResult $who "countnear $m 12"
                if ($r -and $r.result -match 'me=(\d+) visible=(\d+)') { $total += [int]$Matches[1]; $visible += [int]$Matches[2] }
            }
            $seen[$who] = "$visible visible of $total"
            Write-Host "    $who sees barbers: $($seen[$who]) (area $((Status $who).area))"
        }
        $okH = $seen['host'] -match '^1 visible'; $okP = $seen['partner'] -match '^1 visible'
        Check 'Both players walking in together each see one barber' ($okH -and $okP) "host: $($seen['host']), partner: $($seen['partner'])"

        # the race doesn't always happen: make the game that did NOT create the barber create a second one on the same
        # spot, as its shop script did, and check that each player still sees one
        $dup = $null; $maker = $null
        foreach ($m in 156, 176, 177) {
            $r = CmdResult 'host' "pedsnear $m 12"
            if ($r -and $r.result -match 'net=(own|copy)') { $dup = $m; $maker = if ($Matches[1] -eq 'own') { 'partner' } else { 'host' }; break }
        }
        if ($dup) { $r = CmdResult $maker "dupnear $dup 12"; Write-Host "    the $maker's game makes a second barber: $($r.result)" }
        Start-Sleep 4
        $seen2 = @{}
        foreach ($who in 'host', 'partner') {
            $r = CmdResult $who "countnear $dup 12"
            $seen2[$who] = if ($r -and $r.result -match 'me=(\d+) visible=(\d+)') { "$($Matches[2]) visible of $($Matches[1])" } else { "?" }
        }
        foreach ($who in 'host', 'partner') { $r = CmdResult $who "pedsnear $dup 12"; Write-Host "    ${who}: $($r.result)" }
        Check 'With two barbers made, each player still sees one' ($dup -and $seen2['host'] -eq '1 visible of 2' -and $seen2['partner'] -eq '1 visible of 2') "model $dup, host: $($seen2['host']), partner: $($seen2['partner'])"
    }
    else { Check 'Both players walking in together each see one barber' $false 'BARBERS door not found' }
    Cmd 'host' 'interior 0'; Cmd 'partner' 'interior 0'; Start-Sleep 2
    Cmd 'host' 'teleport 2495 -1660 13.5'; Cmd 'partner' 'teleport 2400 -1655 13.6'; Start-Sleep 4
    }

    if ($Parts -contains "marker") {
    # --- the partner starts Big Smoke from its marker, the host far away -----------------------------------------------
    Cmd 'host' 'teleport 2330 -1660 13.5'; Start-Sleep 3
    $hf = Count 'host'
    Cmd 'partner' 'teleport 2495.2 -1687.0 13.5'
    $byPartner = WaitEv 'host' $hf { param($x) $x.ev -eq 'marker_by_partner' } 20
    $started = WaitFor { (Status 'host').onMission } 20
    Check 'The partner standing in the mission marker starts the mission on the host' ($byPartner -and $started) "marker event=$([bool]$byPartner), host on mission=$started, host at $((Pos 'host').x) $((Pos 'host').y)"
    Start-Sleep 6; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 4
    Check 'The mission ends again (fail)' (EndMission) ''
    [void](Wait-Playable { Status 'host' } 60); [void](Wait-Playable { Status 'partner' } 60)
    Cmd 'partner' 'teleport 2400 -1655 13.6'; Start-Sleep 8
    }

    if ($Parts -contains "request") {
    # --- /mission from the partner ------------------------------------------------------------------------------------
    $hf = Count 'host'
    [void](CmdResult 'partner' 'chat /mission big smoke')
    $req = WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_start_by_request' } 15
    $started = WaitFor { (Status 'host').onMission } 15
    Check '/mission big smoke from the partner starts it on the host' ($req -and $started) "request event=$([bool]$req), host on mission=$started"
    Start-Sleep 6; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 4
    Check 'The mission ends again (fail)' (EndMission) ''
    [void](Wait-Playable { Status 'host' } 60); [void](Wait-Playable { Status 'partner' } 60)
    }

    if ($Parts -contains "tags") {
    # --- tags: the partner sprays, the host's game gets it (partial + finished, through the spray sender) --------------
    Cmd 'host' 'teleport 2495 -1660 13.5'; Cmd 'partner' 'teleport 2497 -1662 13.5'; Start-Sleep 4
    $t0 = (Status 'host').collectibles.tagsDone
    $spray = CmdResult 'partner' 'spraytag'
    Start-Sleep 3
    $t1 = (Status 'host').collectibles.tagsDone
    Check "The partner's sprayed tag shows as done on the host" ($spray -and $spray.result -ne 'none' -and $t1 -eq $t0 + 1) "spray=$($spray.result), host tags done $t0 -> $t1"
    }

    if ($Parts -contains "hospital") {
    # --- hospital tip: both die, respawn, walk into the tip at the County General door ---------------------------------
    Cmd 'host' 'teleport 2030 -1415 17.0'; Cmd 'partner' 'teleport 2032 -1415 17.0'; Start-Sleep 3
    [void](CmdResult 'host' 'kill'); [void](CmdResult 'partner' 'kill')
    $ph = Wait-Playable { Status 'host' } 80; $pp = Wait-Playable { Status 'partner' } 80
    Write-Host "    playable again after respawn: host $ph s, partner $pp s"
    Cmd 'host' 'teleport 2027.77 -1420.52 16.99'; Cmd 'partner' 'teleport 2027.77 -1421.5 16.99'; Start-Sleep 4
    $sh = Status 'host'; $sp = Status 'partner'
    $locked = @($sh, $sp | Where-Object { $_.widescreen -or $_.controlsDisabled })
    Check 'After respawning together, the hospital tip leaves both players in control' ($null -ne $ph -and $null -ne $pp -and $locked.Count -eq 0) "host widescreen=$($sh.widescreen) ctrlOff=$($sh.controlsDisabled), partner widescreen=$($sp.widescreen) ctrlOff=$($sp.controlsDisabled)"
    }
}
catch { Check 'Playtest fixes test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
