# Shared helpers for lab.ps1 / lab-cmd.ps1 (dot-source this file).

$LabRoot = Split-Path -Parent $PSScriptRoot
$LabBin = Join-Path $LabRoot 'CoopAndreas\build\windows\x86\release'
if (-not $GameDir) { $GameDir = Join-Path (Split-Path -Parent $LabRoot) 'GTA San Andreas (test)' }
# never the game someone plays: tests run on the copies made by make-test-copies.ps1. playthrough.ps1 defaulted to the
# real game folder and ran there (2026-10-26). Only a script that sets $AllowRealGame = $true first (crash-test.ps1,
# which checks the real game's crash handling on purpose) may.
if ((Split-Path -Leaf $GameDir.TrimEnd('\', '/')) -in @('GTA San Andreas', 'GTA San Andreas (partner)') -and -not $AllowRealGame) {
    throw "Refusing to run a test on the real game folder ($GameDir). Use the test copy 'GTA San Andreas (test)'."
}
$LabAutoDir = Join-Path $GameDir 'CoopAndreas\autotest'
$LabCrashDir = Join-Path $GameDir 'CoopAndreas_crashes'
$LabResults = New-Object System.Collections.ArrayList
# test games start minimized (-autohide) unless COOP_LAB_VISIBLE=1; no focusing/screenshots while hidden
$LabHidden = -not $env:COOP_LAB_VISIBLE
$LabHideArg = if ($LabHidden) { '-autohide' } else { '' }
$script:EventCursor = 0

if (-not ('LabShot' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class LabShot {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    public static bool Focus(IntPtr hwnd) { if (hwnd == IntPtr.Zero) return false; ShowWindow(hwnd, 9); return SetForegroundWindow(hwnd); }
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    // the game window's own contents only (PrintWindow): copying the screen area captured whatever covered the
    // game - the user's desktop - when the window wasn't in front
    public static string Capture(IntPtr hwnd, string path) {
        if (hwnd == IntPtr.Zero) return "no window";
        RECT r; GetWindowRect(hwnd, out r);
        int w = r.R - r.L, h = r.B - r.T; if (w <= 0 || h <= 0) return "bad rect";
        using (var bmp = new Bitmap(w, h)) {
            using (var g = Graphics.FromImage(bmp)) { IntPtr dc = g.GetHdc(); PrintWindow(hwnd, dc, 2); g.ReleaseHdc(dc); }
            bmp.Save(path, ImageFormat.Png);
        }
        return "ok";
    }
}
"@
}

function Read-Status {
    try { return Get-Content (Join-Path $LabAutoDir 'status.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { return $null }
}

# Returns a status at least $ms game-ticks newer than $old (or the latest one after $seconds).
function Wait-StatusAdvance($old, [int]$ms, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do {
        Start-Sleep -Milliseconds 250
        $s = Read-Status
        if ($s -and $old -and ($s.tick - $old.tick) -ge $ms) { return $s }
    } while ((Get-Date) -lt $deadline)
    return Read-Status
}

function Focus-Game {
    if ($LabHidden -or -not $script:Game -or $script:Game.HasExited) { return }
    $script:Game.Refresh()
    [void][LabShot]::Focus($script:Game.MainWindowHandle)
}

function Read-AllEvents {
    $path = Join-Path $LabAutoDir 'events.jsonl'
    if (-not (Test-Path $path)) { return @() }
    $lines = @(Get-Content $path -ErrorAction SilentlyContinue)
    return @($lines | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
}

# Waits for `count` new events of a type (after the cursor), returns them and advances the cursor past them.
function Wait-Events([string]$type, [int]$count, [int]$seconds, [scriptblock]$filter = { $true }) {
    $deadline = (Get-Date).AddSeconds($seconds)
    $found = @()
    do {
        $all = Read-AllEvents
        $found = @()
        for ($i = $script:EventCursor; $i -lt $all.Count; $i++) {
            if ($all[$i].ev -eq $type -and (& $filter $all[$i])) {
                $found += $all[$i]
                if ($found.Count -ge $count) { $script:EventCursor = $i + 1; return $found }
            }
        }
        if ($script:Game -and $script:Game.HasExited) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    return $found
}

function Wait-Event([string]$type, [int]$seconds, [scriptblock]$filter = { $true }) {
    $r = @(Wait-Events $type 1 $seconds $filter)
    if ($r.Count -gt 0) { return $r[0] } else { return $null }
}

function Last-Events([int]$n) {
    (Read-AllEvents | Select-Object -Last $n | ForEach-Object { $_.ev }) -join ' > '
}

function Send-Command([string]$line) {
    # the game reads commands.txt 10x a second (and antivirus may scan it): append with shared access, retry up to 5 s
    $path = Join-Path $LabAutoDir 'commands.txt'
    $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n")
    for ($i = 0; $i -lt 100; $i++) {
        try {
            $fs = [IO.File]::Open($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
            try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
            return
        }
        catch { Start-Sleep -Milliseconds 50 }
    }
    Write-Warning "could not write command: $line"
}

function Shot([string]$name) {
    if ($LabHidden) { return }
    if (-not $script:Game) { $script:Game = Get-Process gta_sa -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $script:Game -or $script:Game.HasExited) { return }
    $script:Game.Refresh()
    $file = Join-Path $script:ReportDir "$name.png"
    [void][LabShot]::Capture($script:Game.MainWindowHandle, $file)
    Write-Host "    screenshot: $file"
}

function Check([string]$name, [bool]$pass, [string]$detail) {
    [void]$LabResults.Add([pscustomobject]@{ check = $name; pass = $pass; detail = $detail })
    Write-Host ("[{0}] {1}{2}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $name, $(if ($detail) { " - $detail" } else { '' }))
    if (-not $pass -or $script:AlwaysShots) { Shot (($LabResults.Count).ToString('00') + '_' + ($name -replace '[^A-Za-z0-9]+', '_')) }
}

# Waits until a player can play again after a death: alive, not dying, no widescreen scene, controls on, for 3 s in a
# row (the first death of a game plays the hospital tutorial, ~25 s with no control). $getStatus returns the
# player's status. Returns the seconds waited, or $null if not playable within $seconds.
function Wait-Playable([scriptblock]$getStatus, [int]$seconds = 60) {
    $t0 = Get-Date; $okSince = $null
    while (((Get-Date) - $t0).TotalSeconds -lt $seconds) {
        $s = & $getStatus
        $ok = $s -and $s.local.health -gt 0 -and $s.pad.pedState -ne 55 -and $s.pad.pedState -ne 54 -and -not $s.widescreen -and -not $s.controlsDisabled
        if (-not $ok) { $okSince = $null } elseif (-not $okSince) { $okSince = Get-Date } elseif (((Get-Date) - $okSince).TotalSeconds -ge 3) { return [math]::Round(($okSince - $t0).TotalSeconds, 1) }
        Start-Sleep -Milliseconds 500
    }
    $null
}

# A check for a known, documented gap: reported as GAP (or FIXED once it passes), never fails the run.
function Known([string]$name, [bool]$pass, [string]$detail) {
    [void]$LabResults.Add([pscustomobject]@{ check = $name; pass = $true; known = $true; fixed = $pass; detail = $detail })
    Write-Host ("[{0}] {1} - {2}" -f $(if ($pass) { 'FIXED' } else { 'GAP ' }), $name, $detail)
}

# Human-readable event timeline, relative to the first event.
function Write-Timeline([string]$path) {
    $all = Read-AllEvents
    if ($all.Count -eq 0) { return }
    $start = $all[0].t
    $lines = $all | ForEach-Object {
        $rest = ($_.PSObject.Properties | Where-Object { $_.Name -notin 't', 'ev' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '
        '{0,7:N1}s  {1,-20} {2}' -f (($_.t - $start) / 1000.0), $_.ev, $rest
    }
    $lines | Set-Content $path -Encoding utf8
}
