# Makes "GTA San Andreas (partner)" next to the game: a hard-link mirror (no extra disk space) used to run a
# second game instance for lab-duo.ps1. Two instances from ONE folder crash the 2nd one inside modloader.asi
# (+0xA34E) because they share modloader's working files, so modloader\, *.ini and the coop autotest/crash
# folders are real copies; everything else is hard-linked. Re-run after deploying a new build.
#
#   powershell -ExecutionPolicy Bypass -File testing\make-partner-copy.ps1

param(
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas')
)

$ErrorActionPreference = 'Stop'
$dst = "$GameDir (partner)"
$srcFull = (Resolve-Path $GameDir).Path

$copied = 0; $linked = 0
foreach ($item in Get-ChildItem $srcFull -Recurse -Force) {
    $rel = $item.FullName.Substring($srcFull.Length + 1)
    if ($rel -like 'CoopAndreas\autotest*' -or $rel -like 'CoopAndreas_crashes*') { continue }
    $target = Join-Path $dst $rel
    if ($item.PSIsContainer) { New-Item -ItemType Directory -Force $target | Out-Null; continue }

    $mustCopy = $rel -like 'modloader\*' -or $item.Extension -in '.ini', '.log', '.set', '.txt'
    if (Test-Path $target) { Remove-Item $target -Force }
    if ($mustCopy) { Copy-Item $item.FullName $target; $copied++ }
    else { New-Item -ItemType HardLink -Path $target -Target $item.FullName | Out-Null; $linked++ }
}
# modloader.asi also crashes (+0xA34E, right after "Parsing command line") when another game instance is already
# running, even from another folder. The partner copy loads the essentials directly from scripts\ instead.
$ml = Join-Path $dst 'modloader.asi'
if (Test-Path $ml) { Remove-Item $ml -Force }
New-Item -ItemType Directory -Force (Join-Path $dst 'scripts') | Out-Null
Get-ChildItem (Join-Path $dst 'modloader\_ESSENTIALS') -Recurse -File -Include *.asi, *.ini | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $dst "scripts\$($_.Name)") -Force
}
Write-Host "partner copy: $dst ($linked hard links, $copied copies; modloader off, essentials in scripts\)"
