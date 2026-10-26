# Reproduces "can't move after alt-tab during a cutscene" on the test copy (one game, own port): walks with W
# through the real keyboard messages, then starts a mission, sends the window focus-loss messages Alt+Tab produces
# during its cutscene, skips it, gives focus back and tries to walk again.
#   powershell -ExecutionPolicy Bypass -File testing\alttab-repro.ps1 [-Mission 13]
param([int]$Mission = 13, [int]$Port = 16797, [switch]$NoAltTab, [string]$Only = "",
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$report = Join-Path $PSScriptRoot ("reports\alttab-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')); New-Item -ItemType Directory -Force $report | Out-Null
$script:ReportDir = $report
$dir = Join-Path $GameDir 'CoopAndreas\autotest\host'
function Events { $p = Join-Path $dir 'events.jsonl'; if (-not (Test-Path $p)) { return @() }; @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} }) }
function Status { try { Get-Content (Join-Path $dir 'status.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null } }
function Cmd($line) { $path = Join-Path $dir 'commands.txt'; $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n"); for ($i = 0; $i -lt 100; $i++) { try { $fs = [IO.File]::Open($path, 'Append', 'Write', 'ReadWrite, Delete'); try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }; return } catch { Start-Sleep -Milliseconds 50 } } }
function WaitEv([int]$from, [scriptblock]$cond, [int]$seconds) { $deadline = (Get-Date).AddSeconds($seconds); do { $all = Events; for ($i = $from; $i -lt $all.Count; $i++) { if (& $cond $all[$i]) { return $all[$i] } }; Start-Sleep -Milliseconds 300 } while ((Get-Date) -lt $deadline); $null }

if (-not ('WinMsg' -as [type])) {
    Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class WinMsg {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    public static IntPtr GameWindow(uint pid) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); var c = new StringBuilder(64); GetClassName(h, c, 64);
            if (p == pid && c.ToString() == "Grand theft auto San Andreas") { found = h; return false; } return true; }, IntPtr.Zero);
        return found;
    }
}
"@
}
function Post($h, [uint32]$msg, [int64]$w, [int64]$l) { [void][WinMsg]::PostMessage($h, $msg, [IntPtr]$w, [IntPtr]$l) }
function WalkW($h) {
    # W key down (repeated like a held key), then up: scan code 0x11 in lParam bits 16-23
    $down = 0x11 -shl 16 -bor 1; $up = $down -bor 0xC0000000
    $p0 = (Status).local
    Post $h 0x0100 0x57 $down
    for ($i = 0; $i -lt 15; $i++) { Start-Sleep -Milliseconds 100; Post $h 0x0100 0x57 ($down -bor 0x40000000) }
    Post $h 0x0101 0x57 $up
    Start-Sleep -Milliseconds 700
    $p1 = (Status).local
    [Math]::Sqrt([Math]::Pow($p1.x - $p0.x, 2) + [Math]::Pow($p1.y - $p0.y, 2))
}

Get-ChildItem $dir -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -Confirm:$false; New-Item -ItemType Directory -Force $dir | Out-Null
$work = Join-Path $env:TEMP "coopandreas-alttab-$Port"; New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden
$game = Start-Process (Join-Path $GameDir 'gta_sa.exe') -WorkingDirectory $GameDir -PassThru -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname host -autodir host"
try {
    if (-not (WaitEv 0 { param($x) $x.ev -eq 'host_gained' } 90)) { throw 'game did not connect' }
    Start-Sleep 15
    $h = [WinMsg]::GameWindow([uint32]$game.Id)
    Cmd 'teleport 2495 -1660 13.5'; Start-Sleep 3
    $d = WalkW $h
    Check 'Baseline: W walks the player (real keyboard messages)' ($d -gt 1) ("moved {0:N1} m" -f $d)

    $f = (Events).Count
    Cmd "startmission $Mission"
    $cs = WaitEv $f { param($x) $x.ev -eq 'cutscene_started' } 30
    Check "Mission $Mission cutscene starts" ([bool]$cs) "$($cs.name)"
    Start-Sleep 2
    # what Alt+Tab sends the game: WM_ACTIVATEAPP(false), WM_KILLFOCUS, with Alt down at that moment
    if (-not $NoAltTab) {
        if ($Only) { foreach ($m in $Only.Split(",")) { Post $h ([Convert]::ToUInt32($m, 16)) 0 0 } }
        else {
        Post $h 0x0104 0x12 (0x38 -shl 16 -bor 1)   # WM_SYSKEYDOWN Alt
        Post $h 0x0104 0x09 (0x0F -shl 16 -bor 1 -bor 0x20000000)   # Alt+Tab
        Post $h 0x001C 0 0; Post $h 0x0008 0 0 }
    }
    Start-Sleep 2
    Cmd 'skipcutscene'
    WaitEv $f { param($x) $x.ev -eq 'cutscene_ended' } 15 | Out-Null
    Start-Sleep 8
    if (-not $NoAltTab) { Post $h 0x001C 1 0; Post $h 0x0007 0 0 }   # back: WM_ACTIVATEAPP(true), WM_SETFOCUS (no Alt key-up: it went to the other window)
    Start-Sleep 2
    $s = Status
    Write-Host ("    pad before walking: " + ($s.pad | ConvertTo-Json -Compress))
    $d = WalkW $h
    Check 'After alt-tab during the cutscene: W still walks the player' ($d -gt 1) ("moved {0:N1} m; controlsDisabled={1} cutscene='{2}' onMission={3}" -f $d, $s.controlsDisabled, $s.cutscene, $s.onMission)
}
finally { if (-not $game.HasExited) { Stop-Process -Id $game.Id -Force }; if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force } }
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
Write-Host ("{0} passed, {1} failed. Report: {2}" -f ($LabResults.Count - $failed), $failed, $report)
exit $failed
