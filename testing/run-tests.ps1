# Automated multiplayer tests for CoopAndreas, no game needed.
# Starts a throwaway server on a test port and drives it with headless bots
# (CoopAndreasBot.exe), which speak the real network protocol.
#
#   powershell -ExecutionPolicy Bypass -File testing\run-tests.ps1
#
# Exit code 0 = all tests passed.

param(
    [int]$Port = 16767,
    [int]$MaxPlayers = 4
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bin = Join-Path $root 'CoopAndreas\build\windows\x86\release'
$serverExe = Join-Path $bin 'server.exe'
$botExe = Join-Path $bin 'CoopAndreasBot.exe'

foreach ($f in $serverExe, $botExe) {
    if (-not (Test-Path $f)) { throw "Missing $f - run testing\build.ps1 first" }
}

# isolated server folder so the test config never touches a real one
$work = Join-Path $env:TEMP "coopandreas-test-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item $serverExe $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = $MaxPlayers`n" -Encoding ascii

$results = @()

function Start-Server {
    $p = Start-Process -FilePath (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $work 'server.log') -RedirectStandardError (Join-Path $work 'server.err')
    Start-Sleep -Milliseconds 800
    if ($p.HasExited) { throw "Server exited at startup, see $work\server.log" }
    return $p
}

function Start-Bot([string]$name, [int]$index, [int]$duration, [string[]]$extra, [string]$logName = $name) {
    $out = Join-Path $work "$logName.log"
    $botArgs = @('--port', $Port, '--name', $name, '--index', $index, '--duration', $duration) + $extra
    return Start-Process -FilePath $botExe -ArgumentList $botArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $out `
        -RedirectStandardError (Join-Path $work "$logName.err")
}

function Get-BotResult([string]$logName) {
    $line = Get-Content (Join-Path $work "$logName.log") -ErrorAction SilentlyContinue | Where-Object { $_ -like 'RESULT *' } | Select-Object -Last 1
    if (-not $line) { return [pscustomobject]@{ name = $name; pass = $false; status = 'no_result'; peers = @() } }
    return ($line.Substring(7) | ConvertFrom-Json)
}

function Add-Result([string]$test, [bool]$pass, [string]$detail) {
    $script:results += [pscustomobject]@{ Test = $test; Pass = $pass; Detail = $detail }
    $mark = if ($pass) { 'PASS' } else { 'FAIL' }
    Write-Host ("[{0}] {1} - {2}" -f $mark, $test, $detail)
}

$server = Start-Server
try {
    # 1. Four players join, see each other move and chat
    $bots = 1..$MaxPlayers | ForEach-Object { Start-Bot "Player$_" ($_ - 1) 12 @('--expect-peers', ($MaxPlayers - 1)) }
    Start-Sleep -Seconds 3

    # 2. A fifth player is refused while the server is full
    $extra = Start-Bot 'Player5' 4 4 @('--expect-refused')
    $extra.WaitForExit()
    $r5 = Get-BotResult 'Player5'
    Add-Result "Player $($MaxPlayers + 1) refused when full" ([bool]$r5.pass) "status=$($r5.status)"

    $bots | ForEach-Object { $_.WaitForExit() }
    foreach ($i in 1..$MaxPlayers) {
        $r = Get-BotResult "Player$i"
        $peerInfo = ($r.peers | ForEach-Object { "$($_.name):$($_.onfoot) moves/$($_.chat) chat" }) -join ', '
        Add-Result "Player$i sees $($MaxPlayers - 1) others moving + chatting" ([bool]$r.pass) "id=$($r.id) $peerInfo"
    }

    # 3. Slots free up after everyone leaves, so a new session can fill the server again
    Start-Sleep -Seconds 2
    $bots = 1..$MaxPlayers | ForEach-Object { Start-Bot "Again$_" ($_ - 1) 8 @('--expect-peers', ($MaxPlayers - 1), '--no-chat') }
    $bots | ForEach-Object { $_.WaitForExit() }
    $again = 1..$MaxPlayers | ForEach-Object { Get-BotResult "Again$_" }
    $okCount = ($again | Where-Object { $_.pass }).Count
    Add-Result 'Server refills after all players leave' ($okCount -eq $MaxPlayers) "$okCount/$MaxPlayers bots passed"

    # 4. Duplicate nickname is rejected (the 2nd one gets kicked with name_taken)
    $a = Start-Bot 'SameName' 0 6 @('--no-chat') 'SameNameA'
    Start-Sleep -Seconds 1
    $b = Start-Bot 'SameName' 1 3 @('--no-chat') 'SameNameB'
    $b.WaitForExit()
    $dup = Get-BotResult 'SameNameB'
    Add-Result 'Duplicate nickname rejected' ($dup.status -eq 'name_taken') "status=$($dup.status)"
    $a.WaitForExit()

    # 5. Server is still alive after all of the above
    Add-Result 'Server survived all tests' (-not $server.HasExited) "pid=$($server.Id)"
}
finally {
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}

$failed = ($results | Where-Object { -not $_.Pass }).Count
Write-Host ''
Write-Host ("{0} passed, {1} failed. Logs: {2}" -f ($results.Count - $failed), $failed, $work)
exit $failed
