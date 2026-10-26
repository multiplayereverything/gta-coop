# Save sync: whoever saves, everyone gets the host's save in that slot; each player keeps their own look.
# Test games save into their own folder (autotest\<who>\docs); the real Documents saves must stay untouched.
#   powershell -ExecutionPolicy Bypass -File testing\save-sync.ps1
param([int]$Port = 16790, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\savesync-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-savesync-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

$realDocs = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GTA San Andreas User Files'
function DocsState { Get-ChildItem $realDocs -File -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)" } }
$realBefore = (DocsState) -join ';'
function Hash($path) { if (Test-Path $path) { (Get-FileHash $path).Hash } else { 'missing' } }
function SavedPath($who, $slot, $from) { $e = Events $who | Select-Object -Skip $from | Where-Object { ($_.ev -eq 'game_saved' -or $_.ev -eq 'save_received') -and $_.slot -eq $slot } | Select-Object -Last 1; if ($e) { $e.path } else { $null } }
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    Start-Sleep 15
    Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2499 -1670 13.5'; Start-Sleep 3

    # the partner looks different from the host
    $pfat = (CmdResult 'partner' 'fat 700').result; $hfat = (CmdResult 'host' 'fat 50').result

    # 1. the host saves: the partner gets the same file
    $hf = Count 'host'; $pf = Count 'partner'
    [void](CmdResult 'host' 'save 7')
    $rcv = WaitEv 'partner' $pf { param($x) $x.ev -eq 'save_received' } 20
    $hp = SavedPath 'host' 7 $hf; $pp = if ($rcv) { $rcv.path } else { '' }
    Check 'Host saves: the partner gets the same save in that slot' ($rcv -and $rcv.ok -and $hp -and (Hash $hp) -eq (Hash $pp)) "host $hp, partner $pp"
    Check 'Test games save into their own folder, not your Documents' ($hp -like '*coopt-host*' -and $pp -like '*coopt-partner*') "$hp | $pp"

    # 2. loading that save keeps each player's own look
    $pl = (CmdResult 'partner' 'lookfrom 7').result; $hl = (CmdResult 'host' 'lookfrom 7').result
    Check 'Loading the shared save gives each player their own look' ($pl -like '*fat=700*' -and $hl -like '*fat=50*') "partner: $pl ($pfat), host: $hl ($hfat)"

    # 3. the partner saves: the host saves that slot and shares it
    $hf = Count 'host'; $pf = Count 'partner'
    [void](CmdResult 'partner' 'save 6')
    $shared = WaitEv 'host' $hf { param($x) $x.ev -eq 'save_shared' -and $x.slot -eq 6 } 20
    $rcv6 = WaitEv 'partner' $pf { param($x) $x.ev -eq 'save_received' -and $x.slot -eq 6 } 20
    $hp6 = SavedPath 'host' 6 $hf
    Check 'Partner saves: the host saves too and everyone gets it' ($shared -and $rcv6 -and $rcv6.ok -and (Hash $hp6) -eq (Hash $rcv6.path)) "host shared: $([bool]$shared), partner got: $([bool]$rcv6)"

    # 4. host on a mission: not shared (a save in the middle of a mission would be broken)
    $hf = Count 'host'
    Cmd 'host' 'startmission 13'; Start-Sleep 6
    $pf = Count 'partner'
    [void](CmdResult 'partner' 'save 5')
    Start-Sleep 6
    $bad = WaitEv 'host' $hf { param($x) $x.ev -eq 'save_shared' -and $x.slot -eq 5 } 2
    Check 'Partner saves while the host is on a mission: nothing is shared' (-not $bad -and (Status 'host').onMission) "onMission=$((Status 'host').onMission)"
    EndMission; Start-Sleep 4

    # 5. the partner starts its game by loading the shared slot (Load Game): the host's story, the partner's own look
    [void](CmdResult 'partner' 'fat 300')   # looks different now than when the save was stored (700)
    Stop-Process -Id $partner.Id -Force; Start-Sleep 15   # the server drops the old connection
    Remove-Item (Join-Path (AutoDir 'partner') 'commands.txt') -Force -ErrorAction SilentlyContinue   # not the old commands again
    $dir = GameDirOf 'partner'
    $partner = Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname partner2 -autodir partner -autoload 7"
    $pf = Count 'partner'
    $loaded = WaitEv 'partner' $pf { param($x) $x.ev -eq 'save_loaded' } 120
    $auth = WaitEv 'partner' $pf { param($x) $x.ev -eq 'authenticated' } 60
    Start-Sleep 5
    $fat = (CmdResult 'partner' 'fat').result
    Check 'Partner starts by loading the shared save: its own look comes back' ($loaded -and $loaded.look -and $fat -eq 'fat=700') "loaded: $([bool]$loaded) look: $($loaded.look) $fat, connected: $([bool]$auth)"}
catch { Check 'Save sync test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    Check 'Your real save folder is unchanged' (((DocsState) -join ';') -eq $realBefore) $realDocs
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
