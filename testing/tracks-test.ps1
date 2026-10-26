# User tracks: songs one player has show up in the other players' User Tracks folder (both directions, a
# non-ASCII name, an existing file is never overwritten). Test games use %TEMP%\coopt-<who>, never your Documents.
#   powershell -ExecutionPolicy Bypass -File testing\tracks-test.ps1
param([int]$Port = 16787, [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\tracks-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
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
$work = Join-Path $env:TEMP "coopandreas-tracks-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }

$hostTracks = Join-Path $env:TEMP 'coopt-host\GTA San Andreas User Files\User Tracks'
$partnerTracks = Join-Path $env:TEMP 'coopt-partner\GTA San Andreas User Files\User Tracks'
$realTracks = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'GTA San Andreas User Files\User Tracks'
$realBefore = (Get-ChildItem $realTracks -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)|$($_.Length)" }) -join ';'
# real (silent) audio: the test games play these on the user-track radio, and random bytes named .mp3 froze the
# game when that station stopped (usertrack-hang.ps1). .wav = PCM, .mp3 = ID3 tag + silent MPEG-1 layer 3 frames.
function Song($path, [int]$kb, [int]$seed) {
    $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    if ($path -like '*.mp3') {
        $w.Write([byte[]](0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 0))   # ID3v2.3, no frames
        $frame = New-Object byte[] 417; $frame[0] = 0xFF; $frame[1] = 0xFB; $frame[2] = 0x90; $frame[3] = 0x04 + ($seed % 2)
        for ($i = 0; $i -lt [int]($kb * 1024 * 5 / 417); $i++) { $w.Write($frame) }   # x5: long enough not to end mid-test
    }
    else {
        $n = $kb * 1024 * 20 + 2 * $seed; $rate = 22050   # x20: about a minute, a short song ends and the radio goes off between songs
        $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
        $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1); $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16)
        $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$n); $w.Write((New-Object byte[] $n))
    }
    $w.Flush(); [IO.File]::WriteAllBytes($path, $ms.ToArray())
}
function Noise($path, [int]$kb, [int]$seed) { $r = New-Object Random $seed; $b = New-Object byte[] ($kb * 1024); $r.NextBytes($b); [IO.File]::WriteAllBytes($path, $b) }
foreach ($d in $hostTracks, $partnerTracks) { New-Item -ItemType Directory -Force $d | Out-Null; Get-ChildItem $d -File | Remove-Item -Force -Confirm:$false }
Song (Join-Path $hostTracks 'coop test song.mp3') 900 1
Song (Join-Path $hostTracks ([string][char]0x00C9 + 'tude n' + [char]0x00B0 + '2.wav')) 120 2
Song (Join-Path $hostTracks 'same name.wav') 50 3
Noise (Join-Path $hostTracks 'notes.txt') 2 4
Noise (Join-Path $hostTracks 'not really a song.mp3') 300 7   # random bytes: must not be shared
Song (Join-Path $partnerTracks 'partner song.mp3') 200 5
Song (Join-Path $partnerTracks 'same name.wav') 60 6   # the partner's own file of that name must stay
$partnerOwn = (Get-FileHash (Join-Path $partnerTracks 'same name.wav')).Hash
try {
    $host_ = StartGame 'host'
    if (-not (WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }
    Start-Sleep 12
    $partner = StartGame 'partner'
    if (-not (WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline -and -not ((Status 'partner').userTracksReceived -ge 2 -and (Status 'host').userTracksReceived -ge 1)) { Start-Sleep 3 }
    function Same($name) { $a = Join-Path $hostTracks $name; $b = Join-Path $partnerTracks $name; (Test-Path -LiteralPath $a) -and (Test-Path -LiteralPath $b) -and (Get-FileHash -LiteralPath $a).Hash -eq (Get-FileHash -LiteralPath $b).Hash }
    $uni = [string][char]0x00C9 + 'tude n' + [char]0x00B0 + '2.wav'
    Check "The host's songs arrive on the partner, identical" ((Same 'coop test song.mp3') -and (Same $uni)) "received by partner: $((Status 'partner').userTracksReceived)"
    Check "The partner's songs arrive on the host" (Same 'partner song.mp3') "received by host: $((Status 'host').userTracksReceived)"
    Check 'Only real songs are shared (not notes.txt, not random bytes named .mp3), an existing file is never overwritten' (-not (Test-Path (Join-Path $partnerTracks 'notes.txt')) -and -not (Test-Path (Join-Path $partnerTracks 'not really a song.mp3')) -and (Get-FileHash (Join-Path $partnerTracks 'same name.wav')).Hash -eq $partnerOwn) ''
    Check 'No half-downloaded files are left' (-not (Get-ChildItem $hostTracks, $partnerTracks -Filter *.coopdl -ErrorAction SilentlyContinue)) ''
    Check 'Both games keep running' ((Status 'host').fps -gt 5 -and (Status 'partner').fps -gt 5) "fps $((Status 'host').fps)/$((Status 'partner').fps)"

    # a passenger hears the driver's station (the host's songs too, now that the partner has them)
    Cmd 'host' 'teleport 2495 -1670 13.5'; Cmd 'partner' 'teleport 2498 -1670 13.5'; Start-Sleep 3
    [void](CmdResult 'host' 'vehicle 400'); Start-Sleep 2
    [void](CmdResult 'host' 'radio 3'); Start-Sleep 2   # K-DST
    $enter = (CmdResult 'partner' 'enterpassenger').result
    $deadline = (Get-Date).AddSeconds(30); $t0 = Get-Date; while ((Status 'partner').radioStation -ne 3 -and (Get-Date) -lt $deadline) { Start-Sleep 1 }; Write-Host ("    partner radio on after {0:N0} s" -f ((Get-Date) - $t0).TotalSeconds)
    $h1 = (Status 'host').radioStation; $p1 = (Status 'partner').radioStation; Write-Host "    zone: host $((Status 'host').zoneInfo) | partner $((Status 'partner').zoneInfo)"
    [void](CmdResult 'host' 'radio 12'); Start-Sleep 6   # User Tracks
    $h2 = (Status 'host').radioStation; $p2 = (Status 'partner').radioStation
    $samples = @(); foreach ($k in 1..8) { Start-Sleep 1; $samples += (Status 'partner').radioStation }   # steady, no flipping
    $steady = @($samples | Where-Object { $_ -ne 12 }).Count -eq 0
    Check "A passenger follows the driver's radio station" ($h1 -eq 3 -and $p1 -eq 3) "host/partner $h1/$p1 ($enter)"
    # station 12 plays only songs the passenger's game has scanned (Audio Setup > Scan User Tracks or a restart);
    # songs just received are not scanned yet, so the passenger's radio may stay off
    Known "A passenger hears the driver's user tracks right away" ($h2 -eq 12 -and $steady) "host $h2, partner then $($samples -join ',')"
}
catch { Check 'User track test runs' $false $_.Exception.Message }
finally {
    $n = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($n -le 0) "$n"
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    $realAfter = (Get-ChildItem $realTracks -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)|$($_.Length)" }) -join ';'
    Check 'Your real User Tracks folder is unchanged' ($realAfter -eq $realBefore) $realTracks
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
exit $failed
