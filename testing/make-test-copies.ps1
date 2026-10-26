# Makes two test games next to the real one, so tests run while people play the real game:
#   "GTA San Andreas (test)" and "GTA San Andreas (test) (partner)".
# Game data is hard-linked (no extra disk space, never written); every file a build/scm deploy writes is a REAL copy,
# so deploying into a test copy can never change the real game (a hard-linked target would be overwritten in place).
# modloader is off (it crashes in a second running instance); the essentials load from scripts\.
#
#   powershell -ExecutionPolicy Bypass -File testing\make-test-copies.ps1
#   then build/test with -GameDir "<...>\GTA San Andreas (test)"

param(
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas')
)

$ErrorActionPreference = 'Stop'
$srcFull = (Resolve-Path $GameDir).Path
# written by testing\build.ps1 -Deploy and testing\build-scm.ps1
$deployed = 'eax.dll', 'eax_orig.dll', 'coop_eax.dll', 'CoopAndreasSA.dll', 'LaunchCoopAndreas.exe', 'LaunchCoopAndreas.exe.manifest',
    'CoopAndreas\main.scm', 'CoopAndreas\script.img'

foreach ($dst in "$srcFull (test)", "$srcFull (test) (partner)") {
    $copied = 0; $linked = 0
    foreach ($item in Get-ChildItem $srcFull -Recurse -Force) {
        $rel = $item.FullName.Substring($srcFull.Length + 1)
        if ($rel -like 'CoopAndreas\autotest*' -or $rel -like 'CoopAndreas_crashes*' -or $rel -like 'logs*') { continue }
        $target = Join-Path $dst $rel
        if ($item.PSIsContainer) { New-Item -ItemType Directory -Force $target | Out-Null; continue }
        $mustCopy = $rel -like 'modloader\*' -or $item.Extension -in '.ini', '.log', '.set', '.txt' -or $deployed -contains $rel
        if (Test-Path $target) { Remove-Item $target -Force }
        if ($mustCopy) { Copy-Item $item.FullName $target; $copied++ }
        else { New-Item -ItemType HardLink -Path $target -Target $item.FullName | Out-Null; $linked++ }
    }
    $ml = Join-Path $dst 'modloader.asi'
    if (Test-Path $ml) { Remove-Item $ml -Force }
    New-Item -ItemType Directory -Force (Join-Path $dst 'scripts') | Out-Null
    Get-ChildItem (Join-Path $dst 'modloader\_ESSENTIALS') -Recurse -File -Include *.asi, *.ini | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $dst "scripts\$($_.Name)") -Force
    }
    Write-Host "test copy: $dst ($linked hard links, $copied copies; modloader off)"
}
