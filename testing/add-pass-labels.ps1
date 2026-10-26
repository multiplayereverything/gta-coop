# Adds Coop.SetAutotestPassLabel(@<pass block>) to story mission scripts that lack Rockstar's debug skip
# (is_keyboard_key_pressed 83), so the autotest passmission command can run their pass routine.
# Dry run by default; -Apply writes the scripts. Rebuild main.scm afterwards (testing\build-scm.ps1).
param([switch]$Apply, [switch]$All)
$scm = Join-Path (Split-Path -Parent $PSScriptRoot) 'CoopAndreas\scm'
$main = Get-Content (Join-Path $scm 'main.txt')
foreach ($m in $main | Select-String '^DEFINE MISSION (\d+) AT @(\w+)') {
    $id = [int]$m.Matches[0].Groups[1].Value; $label = $m.Matches[0].Groups[2].Value
    if ($id -lt 11 -or $id -gt 112) { continue }
    $file = Join-Path $scm "scripts\$label.txt"
    if (-not (Test-Path $file)) { continue }
    $lines = [Collections.Generic.List[string]](Get-Content $file)
    $text = $lines -join "`n"
    # -All: also missions that have Rockstar's debug check (it often sits in a late stage the sweep never reaches)
    if ((-not $All -and $text -match 'keyboard_key_pressed 83') -or $text -match '(?m)^1D20:') { continue }
    $reg = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'RegisterMissionPassed|register_mission_passed') { $reg = $i; break } }
    if ($reg -lt 0) { Write-Host ("{0,3} {1,-8} no RegisterMissionPassed" -f $id, $label); continue }
    # walk back to the label that starts the block (not reached by falling through)
    $start = $null
    for ($i = $reg; $i -ge 0; $i--) {
        if ($lines[$i] -match '^:(\w+)') {
            $j = $i - 1
            while ($j -ge 0 -and ($lines[$j].Trim() -eq '' -or $lines[$j].Trim().StartsWith('//'))) { $j-- }
            if ($j -lt 0 -or $lines[$j].Trim() -match '^(return|goto |jump |terminate_this_script|end_thread|terminate_this_custom_script)') { $start = $Matches[1]; $start = ($lines[$i] -replace '^:(\w+).*', '$1'); break }
        }
    }
    # the block must end with return
    $end = ''
    for ($i = $reg; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -match '^(return|goto |terminate_this_script)') { $end = $lines[$i].Trim(); break } }
    Write-Host ("{0,3} {1,-8} pass block @{2} (register at line {3}, block ends '{4}')" -f $id, $label, $start, ($reg + 1), $end)
    if ($Apply -and $start -and $end) {
        $at = -1
        for ($i = 0; $i -lt [Math]::Min(12, $lines.Count); $i++) { if ($lines[$i] -match 'script_name|Coop\.EnableSyncingThisScript') { $at = $i } }
        if ($at -ge 0) { $lines.Insert($at + 1, "1D20: @$start // Coop.SetAutotestPassLabel: autotest passmission jumps to this pass routine"); [IO.File]::WriteAllLines($file, $lines) }
    }
}
