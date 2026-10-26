# Runs a test script and samples the foreground window every 100 ms; reports whether a test game (gta_sa.exe)
# ever became the active window, i.e. whether the run would have interrupted the user.
#
#   powershell -ExecutionPolicy Bypass -File testing\focus-watch.ps1 lab-duo.ps1 [args...]

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot $args[0]
$rest = @($args | Select-Object -Skip 1)

if (-not ('FocusWatch' -as [type])) {
    Add-Type @"
using System; using System.Runtime.InteropServices;
public static class FocusWatch {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
}
"@
}

$job = Start-Process powershell -PassThru -NoNewWindow -ArgumentList (@('-ExecutionPolicy', 'Bypass', '-File', "`"$script`"") + $rest)
$hits = 0; $samples = 0
while (-not $job.HasExited) {
    $pid_ = 0
    [void][FocusWatch]::GetWindowThreadProcessId([FocusWatch]::GetForegroundWindow(), [ref]$pid_)
    $p = Get-Process -Id $pid_ -ErrorAction SilentlyContinue
    if ($p -and $p.Name -eq 'gta_sa') { $hits++ }
    $samples++
    Start-Sleep -Milliseconds 100
}
Write-Host ("focus-watch: game was the foreground window in {0} of {1} samples" -f $hits, $samples)
exit $hits
