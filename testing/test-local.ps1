# Local in-game test: one server + up to 4 game windows on this PC (2x2 grid),
# optionally topped up with headless bots so you always have 4 players.
#
#   powershell -ExecutionPolicy Bypass -File testing\test-local.ps1 -Instances 1 -Bots 3
#   powershell -ExecutionPolicy Bypass -File testing\test-local.ps1 -Instances 2
#
# Needs: testing\build.ps1 -Deploy (no serial key: this fork removed the beta key check).
# In each window: Start Game -> nickname / IP 127.0.0.1 / port below -> Connect.
# Each window remembers its own nickname (coopd<N>_coopandreas.ini in the user files folder).
# Start the game windows first so a real game becomes the host, not a bot.

param(
    [ValidateRange(0, 4)][int]$Instances = 1,
    [ValidateRange(0, 3)][int]$Bots = 3,
    [int]$Port = 6767,
    [int]$BotSeconds = 600,
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)')  # the test copy: never the game someone plays
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'CoopAndreas\build\windows\x86\release'

if ($Instances + $Bots -gt 4) { throw "Instances + Bots must be 4 or fewer (server maxplayers is 4)" }


# server in its own folder with a 4 player cap
$work = Join-Path $env:TEMP "coopandreas-local-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $bin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru
Write-Host "Server pid $($server.Id) on port $Port"

for ($i = 0; $i -lt $Instances; $i++) {
    Start-Process (Join-Path $GameDir 'gta_sa.exe') -WorkingDirectory $GameDir `
        -ArgumentList "--coop --coopd$i"
    Write-Host "Game window $i started (connect to 127.0.0.1:$Port)"
    Start-Sleep -Seconds 3
}

if ($Bots -gt 0) {
    if ($Instances -gt 0) {
        Read-Host "Connect the game window(s) first, then press Enter to add $Bots bot(s)"
    }
    for ($b = 1; $b -le $Bots; $b++) {
        Start-Process (Join-Path $bin 'CoopAndreasBot.exe') -WindowStyle Minimized `
            -ArgumentList "--port $Port --name TestBot$b --index $b --duration $BotSeconds"
    }
    Write-Host "$Bots bot(s) walking in circles near Grove Street (2495, -1670) for $BotSeconds s."
}

Write-Host "Close the server window to end the session."
