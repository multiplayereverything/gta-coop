# Builds coop-dev\friend-package\CoopAndreas-coop4-<date>.zip: everything a friend needs to join (or host) with
# exactly our build, and nothing from the game itself (they need their own GTA SA 1.0 US).
#
#   powershell -ExecutionPolicy Bypass -File testing\make-friend-package.ps1
#
# Contents: game\ (files for their GTA folder + install.bat/uninstall.bat), server\ (for whoever hosts),
# README.txt, LICENSE (GPL-3.0) and source\ (our patches on top of Tornamic/CoopAndreas, GPL source offer).

#   powershell -ExecutionPolicy Bypass -File testing\make-friend-package.ps1 -Source CoopAndreas-stable -Label stable

param(
    [string]$Source = 'CoopAndreas',   # folder under coop-dev (e.g. the CoopAndreas-stable worktree)
    [string]$Label = 'coop4'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root $Source
$bin = Join-Path $src 'build\windows\x86\release'
$stamp = Get-Date -Format 'yyyy-MM-dd'
$out = Join-Path $root "friend-package\CoopAndreas-$Label-$stamp"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Force "$out\game\CoopAndreas", "$out\server", "$out\source" | Out-Null

# client side: our proxy is shipped as coop_eax.dll; install.bat moves their own eax.dll aside
Copy-Item "$bin\proxy.dll" "$out\game\coop_eax.dll"
Copy-Item "$bin\CoopAndreasSA.dll", "$bin\LaunchCoopAndreas.exe", "$bin\LaunchCoopAndreas.exe.manifest" "$out\game\"
Copy-Item "$src\scm\main.scm", "$src\scm\script.img" "$out\game\CoopAndreas\"

Set-Content "$out\game\install.bat" -Encoding ascii @'
@echo off
rem Run this from inside your GTA San Andreas 1.0 US folder (where gta_sa.exe is).
if not exist gta_sa.exe ( echo gta_sa.exe not found - copy these files into your GTA San Andreas folder first & pause & exit /b 1 )
if not exist eax_orig.dll (
  if not exist eax.dll ( echo eax.dll not found - is this GTA San Andreas 1.0? & pause & exit /b 1 )
  ren eax.dll eax_orig.dll
)
copy /y coop_eax.dll eax.dll >nul
if exist CLEO\CLEO+.cleo ( if not exist CLEO\disabled mkdir CLEO\disabled & move /y CLEO\CLEO+.cleo CLEO\disabled\ >nul & echo CLEO+ moved to CLEO\disabled - it breaks shot sync in coop )
echo GTA San Andreas co-op installed. Start it with LaunchCoopAndreas.exe. Normal single player: gta_sa.exe
pause
'@
Set-Content "$out\game\uninstall.bat" -Encoding ascii @'
@echo off
if exist eax_orig.dll ( del /q eax.dll & ren eax_orig.dll eax.dll )
del /q CoopAndreasSA.dll LaunchCoopAndreas.exe LaunchCoopAndreas.exe.manifest coop_eax.dll 2>nul
rmdir /s /q CoopAndreas 2>nul
echo CoopAndreas removed.
pause
'@

# server side
Copy-Item "$bin\server.exe" "$out\server\"
Set-Content "$out\server\server-config.ini" "port = 6767`nmaxplayers = 4`n" -Encoding ascii

# GPL: license + our changes as patches against the upstream commit we forked from
Copy-Item "$src\LICENSE" "$out\LICENSE"
Push-Location $src
try { git format-patch -q df03bbf..HEAD -o "$out\source" | Out-Null } finally { Pop-Location }
Set-Content "$out\source\README.txt" -Encoding ascii @"
Source: https://github.com/Tornamic/CoopAndreas at commit df03bbf, plus the patches in this folder
(git am *.patch). Build with xmake + Visual Studio 2022 (see the upstream README). License: GPL-3.0.
"@

Copy-Item (Join-Path $PSScriptRoot 'friend-README.txt') "$out\README.txt"

$zip = "$out.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$out\*" -DestinationPath $zip
Write-Host ("package: {0} ({1:N1} MB)" -f $zip, ((Get-Item $zip).Length / 1MB))
