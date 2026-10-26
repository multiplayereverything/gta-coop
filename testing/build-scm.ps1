# Compiles CoopAndreas\scm\main.txt (all mission scripts) with Sanny Builder 4 and deploys main.scm + script.img
# to GTA San Andreas\CoopAndreas\ (the coop client loads them from there).
#
#   powershell -ExecutionPolicy Bypass -File testing\build-scm.ps1            # compile + deploy
#   powershell -ExecutionPolicy Bypass -File testing\build-scm.ps1 -Check     # compile only, compare with the repo copy
#
# Setup (done once, see MODLOG): Sanny Builder 4.2 in C:\Tools\SannyBuilder4 with the repo's sdk overlay copied in,
# data\sa_sbl_coopandreas\mode.xml has @game: replaced by the game path, settings.ini EditMode=sa_sbl_coopandreas.
# Unmodified sources compile byte-identical to the shipped main.scm/script.img.

param(
    [switch]$Check,
    [string]$Sanny = 'C:\Tools\SannyBuilder4\sanny.exe',
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas')
)

$ErrorActionPreference = 'Stop'
$scm = Join-Path (Split-Path -Parent $PSScriptRoot) 'CoopAndreas\scm'
$out = Join-Path (Split-Path -Parent $PSScriptRoot) 'CoopAndreas\build\scm'
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out -File | Remove-Item -Force

# Sanny compiles with its own copy of the command definitions: keep it in step with the repo's (a command missing
# there compiled to nothing, without an error)
foreach ($f in 'sa_coop.json', 'sa_coop.db') {
    $src = Join-Path (Split-Path -Parent $PSScriptRoot) "CoopAndreas\sdk\Sanny Builder 4\data\sa_sbl_coopandreas\$f"
    $dst = Join-Path (Split-Path $Sanny) "data\sa_sbl_coopandreas\$f"
    if ((Test-Path $src) -and (-not (Test-Path $dst) -or (Get-FileHash $src).Hash -ne (Get-FileHash $dst).Hash)) { Copy-Item $src $dst -Force; Write-Host "updated Sanny's $f" }
}

$log = Join-Path (Split-Path $Sanny) 'core.log'
$logLines0 = @(Get-Content $log -ErrorAction SilentlyContinue).Count
$p = Start-Process $Sanny -ArgumentList '--no-splash', '--compile', "`"$scm\main.txt`"", "`"$out\main.scm`"" -PassThru
if (-not $p.WaitForExit(300000)) { Stop-Process $p -Force; throw 'Sanny Builder timed out' }
# Sanny logs a few harmless "Invalid number of params for opcode 0D60/0E6B/0E9C" library ERRORs on every start;
# real compile errors name a source file or line
$errors = @(Get-Content $log -ErrorAction SilentlyContinue | Select-Object -Skip $logLines0 |
    Select-String 'ERROR' | Where-Object { $_.Line -match '\.txt|line \d+' })
if (-not (Test-Path "$out\main.scm") -or $errors) {
    $errors | Select-Object -Last 10 | ForEach-Object { Write-Host $_ }
    throw "compile failed, see $log"
}
$same = (Get-FileHash "$out\main.scm").Hash -eq (Get-FileHash "$scm\main.scm").Hash
Write-Host ("compiled main.scm {0} bytes, script.img {1} bytes, identical to repo copy: {2}" -f (Get-Item "$out\main.scm").Length, (Get-Item "$out\script.img").Length, $same)

if ($Check) { exit 0 }

# keep the repo's prebuilt copies in step with the sources, then deploy
Copy-Item "$out\main.scm", "$out\script.img" $scm -Force
$dest = Join-Path $GameDir 'CoopAndreas'
Copy-Item "$out\main.scm", "$out\script.img" $dest -Force
Write-Host "deployed to $dest (restart the game; savegames from older main.scm builds may not load)"
