# Send a command to a running autotest game (lab.ps1 -Keep) and print the events it caused.
#
#   powershell -ExecutionPolicy Bypass -File testing\lab-cmd.ps1 "teleport 2495 -1680 13.4"
#   powershell -ExecutionPolicy Bypass -File testing\lab-cmd.ps1 status
#   powershell -ExecutionPolicy Bypass -File testing\lab-cmd.ps1 events 20
#   powershell -ExecutionPolicy Bypass -File testing\lab-cmd.ps1 shot
#
# Game commands: chat <text> | teleport <x> <y> <z> | vehicle <model> | leavevehicle | heal

param([Parameter(Mandatory)][string]$Command, [int]$Wait = 3)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')
$script:ReportDir = $LabAutoDir

switch -Regex ($Command) {
    '^status$' { Read-Status | ConvertTo-Json -Depth 5; break }
    '^events' {
        $n = if ($Command -match '\d+') { [int]$Matches[0] } else { 15 }
        $tmp = Join-Path $env:TEMP 'lab-timeline.txt'; Write-Timeline $tmp; Get-Content $tmp -Tail $n; break
    }
    '^shot$' { Shot ('shot_' + (Get-Date -Format 'HHmmss')); break }
    default {
        $before = @(Read-AllEvents).Count
        Send-Command $Command
        Start-Sleep -Seconds $Wait
        $all = Read-AllEvents
        $all | Select-Object -Skip $before | ForEach-Object { $_ | ConvertTo-Json -Compress }
        $s = Read-Status
        if ($s) { "status: auth=$($s.authenticated) host=$($s.isHost) fps=$($s.fps) pos=$($s.local.x),$($s.local.y),$($s.local.z) car=$($s.local.inVehicle) players=$(@($s.players).Count)" }
    }
}
