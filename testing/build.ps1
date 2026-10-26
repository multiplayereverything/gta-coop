# Build every CoopAndreas target (release, x86) and optionally deploy into the game folder.
#
#   powershell -ExecutionPolicy Bypass -File testing\build.ps1            # build only
#   powershell -ExecutionPolicy Bypass -File testing\build.ps1 -Deploy    # build + install into the game
#   powershell -ExecutionPolicy Bypass -File testing\build.ps1 -Uninstall # restore the original eax.dll

param(
    [switch]$Deploy,
    [switch]$Uninstall,
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'CoopAndreas'
$bin = Join-Path $src 'build\windows\x86\release'
$backup = Join-Path $root 'backup-original'

# the original eax.dll from the game, used to tell it apart from our proxy
$originalEaxHash = (Get-FileHash (Join-Path $backup 'eax.dll')).Hash

function Restore-Eax {
    $eax = Join-Path $GameDir 'eax.dll'
    $orig = Join-Path $GameDir 'eax_orig.dll'
    if (Test-Path $orig) {
        Copy-Item $orig $eax -Force
        Remove-Item $orig
    }
    foreach ($f in 'CoopAndreasSA.dll', 'LaunchCoopAndreas.exe', 'LaunchCoopAndreas.exe.manifest') {
        $p = Join-Path $GameDir $f
        if (Test-Path $p) { Remove-Item $p }
    }
    Write-Host "Uninstalled. eax.dll restored (hash ok: $((Get-FileHash $eax).Hash -eq $originalEaxHash))."
}

if ($Uninstall) { Restore-Eax; exit 0 }

$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
Push-Location $src
try {
    xmake f -p windows -a x86 -m release -y | Out-Null
    foreach ($t in 'server', 'testbot', 'proxy', 'launcher', 'client') {
        Write-Host "== building $t"
        xmake build -y $t
        if ($LASTEXITCODE -ne 0) { throw "build of $t failed" }
    }
}
finally { Pop-Location }

# a ready-to-host server folder
$serverDir = Join-Path $root 'server'
New-Item -ItemType Directory -Force $serverDir | Out-Null
Copy-Item (Join-Path $bin 'server.exe') $serverDir -Force
if (-not (Test-Path (Join-Path $serverDir 'server-config.ini'))) {
    Set-Content (Join-Path $serverDir 'server-config.ini') "port = 6767`nmaxplayers = 4`n" -Encoding ascii
}

if (-not $Deploy) { Write-Host "Built into $bin (server copied to $serverDir)."; exit 0 }

if (-not (Test-Path (Join-Path $GameDir 'gta_sa.exe'))) { throw "gta_sa.exe not found in $GameDir" }

$eax = Join-Path $GameDir 'eax.dll'
$orig = Join-Path $GameDir 'eax_orig.dll'
if (-not (Test-Path $orig)) {
    if ((Get-FileHash $eax).Hash -ne $originalEaxHash) { throw "eax.dll is not the original and eax_orig.dll is missing; restore from $backup first" }
    Copy-Item $eax $orig
}
Copy-Item (Join-Path $bin 'proxy.dll') $eax -Force
Copy-Item (Join-Path $bin 'CoopAndreasSA.dll') $GameDir -Force
Copy-Item (Join-Path $bin 'LaunchCoopAndreas.exe') $GameDir -Force
Copy-Item (Join-Path $bin 'LaunchCoopAndreas.exe.manifest') $GameDir -Force

$coopDir = Join-Path $GameDir 'CoopAndreas'
New-Item -ItemType Directory -Force $coopDir | Out-Null
Copy-Item (Join-Path $src 'scm\main.scm') $coopDir -Force
Copy-Item (Join-Path $src 'scm\script.img') $coopDir -Force

Write-Host "Deployed to $GameDir. Single player still works by running gta_sa.exe directly; coop via LaunchCoopAndreas.exe."
