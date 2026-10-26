# How each player looks on the other's screen: walk, run, sprint, jump, punch, recorded on both games and checked by
# coop-anything's animcheck (sliding, T-pose, floating, wrong animation, pose error).   powershell -ExecutionPolicy Bypass -File testing\anim-sync.ps1
param([int]$Port = 16806, [double]$PoseTol = 0.3, [switch]$RebuildHost, [switch]$RebuildPartner, [string]$RebuildCmd = 'fat 400', [string]$OtherDir = "", [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\anim-sync-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
New-Item -ItemType Directory -Force $report | Out-Null
$script:ReportDir = $report
$PartnerDir = if ($OtherDir) { $OtherDir } else { "$GameDir (partner)" }  # -GameDir/-OtherDir swap which copy hosts
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
$work = Join-Path $env:TEMP "coopandreas-animsync-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

$Toolkit = Join-Path (Split-Path -Parent $PSScriptRoot) 'toolkit-coop-anything'
$Profile = Join-Path $PSScriptRoot 'animcheck\gtasa-profile.json'
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    $ids = @{ host = (Status 'host').id; partner = (Status 'partner').id }
    # -RebuildHost: the host changes its body first (the others rebuild the host's character, as after a clothes change)
    if ($RebuildHost) { Write-Host "    host: $((CmdResult 'host' $RebuildCmd).result)"; Start-Sleep 4 }
    if ($RebuildPartner) { Write-Host "    partner: $((CmdResult 'partner' $RebuildCmd).result)"; Start-Sleep 4 }
    foreach ($w in 'host', 'partner') { Remove-Item (Join-Path (AutoDir $w) 'anim.probe.jsonl') -Force -Confirm:$false -ErrorAction SilentlyContinue }
    $moving = @()
    foreach ($mover in 'host', 'partner') {
        $other = if ($mover -eq 'host') { 'partner' } else { 'host' }
        # open airport tarmac (in Grove Street CJ ran into walls), the watcher a few metres to the side
        Cmd $mover 'teleport 1700 -2480 13.5'; Cmd $other 'teleport 1700 -2500 13.5'; Start-Sleep 3
        # the mover runs east along y -2480; the watcher looks at that path so the mover stays on its screen
        Cmd $mover 'face 1800 -2480 13.5'; Cmd $other 'face 1730 -2480 13.5'; Start-Sleep 1
        Cmd 'host' 'animprobe on'; Cmd 'partner' 'animprobe on'; Start-Sleep 2
        foreach ($step in @(@{ p = 'walkfwd'; ms = 4000; move = $true }, @{ p = 'fwd'; ms = 4000; move = $true }, @{ p = 'fwd+cross'; ms = 4000; move = $true },
                            @{ p = 'turnl'; ms = 1500; move = $false }, @{ p = 'square'; ms = 300; move = $false }, @{ p = 'circle'; ms = 300; move = $false }, @{ p = 'circle'; ms = 300; move = $false })) {
            $t0 = (Status $mover).tick
            Cmd $mover "press $($step.p) $($step.ms)"; Start-Sleep -Milliseconds ($step.ms + 1500)
            if ($step.move) { $moving += "$($ids[$mover]):$([long]$t0 + 800)-$([long]$t0 + $step.ms - 200)" }
        }
        Start-Sleep 2
        Cmd 'host' 'animprobe off'; Cmd 'partner' 'animprobe off'; Start-Sleep 1
    }
    foreach ($w in 'host', 'partner') { Copy-Item (Join-Path (AutoDir $w) 'anim.probe.jsonl') (Join-Path $report "$w.probe.jsonl") }
    $lines = @{ host = @(Get-Content (Join-Path $report 'host.probe.jsonl')).Count; partner = @(Get-Content (Join-Path $report 'partner.probe.jsonl')).Count }
    Check 'Both games recorded the probe' ($lines.host -gt 100 -and $lines.partner -gt 100) "host $($lines.host) lines, partner $($lines.partner)"
    $avatars = @('--avatar', ("host=host:{0:X}>partner:{0:X}" -f $ids.host), '--avatar', ("partner=partner:{0:X}>host:{0:X}" -f $ids.partner))
    $exp = @(); foreach ($m in $moving) { $exp += @('--expect-moving', $m) }
    $out = & py -3 -I (Join-Path $Toolkit 'tools\animcheck\cli.py') analyze "host=$report\host.probe.jsonl" "partner=$report\partner.probe.jsonl" --profile $Profile @avatars @exp --pose-tol $PoseTol --html (Join-Path $report 'animcheck.html') --json (Join-Path $report 'animcheck.json') 2>&1
    $code = $LASTEXITCODE
    $out | Set-Content (Join-Path $report 'animcheck.txt') -Encoding utf8
    $out | Select-Object -Last 25 | ForEach-Object { Write-Host "    $_" }
    Check 'animcheck: other players look the way they really move (no sliding, T-pose, floating, wrong animation)' ($code -eq 0) "exit $code, report $report\animcheck.html"
}
catch { Check 'Animation sync test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
