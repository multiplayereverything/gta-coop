# Zips the whole coop-ready game folder for friends who own the game, without test leftovers
# (crash logs, autotest files, logs). Adds the coop server and HOW-TO-PLAY.
param([string]$Out = (Join-Path (Split-Path -Parent $PSScriptRoot) ("friend-package\GTA-SA-coop-full-" + (Get-Date -Format 'yyyy-MM-dd') + ".zip")))

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$root = Split-Path -Parent $PSScriptRoot
$game = Join-Path (Split-Path -Parent $root) 'GTA San Andreas'
$skip = @('CoopAndreas_crashes\', 'CoopAndreas_reports\', 'CoopAndreas\autotest\', 'logs\')
if (Test-Path $Out) { Remove-Item $Out -Force }
$zip = [IO.Compression.ZipFile]::Open($Out, 'Create')
try {
    $n = 0
    foreach ($f in Get-ChildItem $game -Recurse -File -Force) {
        $rel = $f.FullName.Substring($game.Length + 1)
        if ($skip | Where-Object { $rel.StartsWith($_, 'OrdinalIgnoreCase') }) { continue }
        if ($f.Extension -eq '.log') { continue }
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, "GTA San Andreas\$rel", 'Optimal')
        $n++
    }
    foreach ($f in Get-ChildItem (Join-Path $root 'CoopAndreas\build\windows\x86\release') -File | Where-Object { $_.Name -like 'server*' }) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, "CoopAndreas Server\$($f.Name)", 'Optimal'); $n++
    }
    $cfg = $zip.CreateEntry('CoopAndreas Server\server-config.ini')
    $w = New-Object IO.StreamWriter($cfg.Open()); $w.Write("port = 6767`r`nmaxplayers = 4`r`n"); $w.Dispose()
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $root 'HOW-TO-PLAY.md'), 'HOW-TO-PLAY.md', 'Optimal')
    "$n files"
}
finally { $zip.Dispose() }
"{0} ({1:N2} GB)" -f $Out, ((Get-Item $Out).Length / 1GB)
