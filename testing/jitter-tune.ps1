# NPC smoothing tuning: host + partner at Grove Street, the partner measures the host's peds with smoothing off and
# at several strengths (20 s each); the host's own peds give the natural-movement baseline. ~4 minutes.
#   powershell -ExecutionPolicy Bypass -File testing\jitter-tune.ps1 [-Strengths "0.15,0.25,0.4,0.6"]
param([string]$Strengths = '0.15,0.25,0.4,0.6', [int]$Port = 16796,
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)')  # the test copy: never the game someone plays)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$PartnerDir = "$GameDir (partner)"
function GameDirOf($who) { if ($who -eq 'partner') { $PartnerDir } else { $GameDir } }
function AutoDir($who) { Join-Path (GameDirOf $who) "CoopAndreas\autotest\$who" }
function Events($who) { $p = Join-Path (AutoDir $who) 'events.jsonl'; if (-not (Test-Path $p)) { return @() }; @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} }) }
function Status($who) { try { Get-Content (Join-Path (AutoDir $who) 'status.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null } }
function Cmd($who, $line) { $path = Join-Path (AutoDir $who) 'commands.txt'; $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n"); for ($i = 0; $i -lt 100; $i++) { try { $fs = [IO.File]::Open($path, 'Append', 'Write', 'ReadWrite, Delete'); try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }; return } catch { Start-Sleep -Milliseconds 50 } } }
function WaitEv($who, [scriptblock]$cond, [int]$seconds) { $deadline = (Get-Date).AddSeconds($seconds); do { foreach ($x in Events $who) { if (& $cond $x) { return $x } }; Start-Sleep -Milliseconds 300 } while ((Get-Date) -lt $deadline); $null }

Get-Process gta_sa -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 1
foreach ($w in 'host', 'partner') { New-Item -ItemType Directory -Force (AutoDir $w) | Out-Null; Remove-Item "$(AutoDir $w)\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
$work = Join-Path $env:TEMP "coopandreas-jitter-$Port"; New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden
function StartGame($who) { $dir = GameDirOf $who; Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who" }
$games = @()
try {
    $games += StartGame 'host'; if (-not (WaitEv 'host' { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'host failed' }; Start-Sleep 12
    $games += StartGame 'partner'; if (-not (WaitEv 'partner' { param($x) $x.ev -eq 'authenticated' } 90)) { throw 'partner failed' }; Start-Sleep 15
    Cmd 'host' 'teleport 2490 -1660 13.5'; Cmd 'partner' 'teleport 2492 -1660 13.5'; Start-Sleep 5
    $runs = @(@{ name = 'off (old snapping)'; cmd = 'smoothing 0' }) + @($Strengths -split ',' | ForEach-Object { @{ name = "strength $_"; cmd = "smoothing 1 $_" } })
    foreach ($r in $runs) {
        Cmd 'partner' $r.cmd; Cmd 'host' 'smoothing 1'; Start-Sleep 20
        $p = Status 'partner'; $h = Status 'host'
        "{0,-20} partner: {1,5:N1}% of moving frames snap back ({2} samples)   host's own peds: {3,5:N1}%" -f $r.name, $p.npcJitterCm, $p.npcJitterSamples, $h.ownNpcJitterCm
    }
}
finally { $games | ForEach-Object { if (-not $_.HasExited) { Stop-Process -Id $_.Id -Force } }; if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
