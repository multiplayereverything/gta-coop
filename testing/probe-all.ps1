# Runs gap-probe.ps1 over many missions in batches of 6 (fresh games per batch) and appends every result line to
# reports\probe-all-<time>.txt. Detached-friendly:  powershell -File testing\probe-all.ps1 -Missions "12,15,26"
param([string]$Missions)
$ids = $Missions.Split(',') | Where-Object { $_ }
$out = Join-Path $PSScriptRoot ("reports\probe-all-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm') + ".txt")
for ($i = 0; $i -lt $ids.Count; $i += 6) {
    $batch = ($ids[$i..([Math]::Min($i + 5, $ids.Count - 1))]) -join ','
    Add-Content $out "== batch $batch $(Get-Date -Format HH:mm:ss)"
    $lines = & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'gap-probe.ps1') -Missions $batch 2>&1
    $lines | Where-Object { $_ -match '^\s+\d+\s|blips:|FAIL|PASS|Report:' } | ForEach-Object { Add-Content $out $_ }
    $rep = ($lines | Where-Object { $_ -match 'Report: (.*)' } | Select-Object -Last 1) -replace '.*Report: ', ''
    if ($rep -and (Test-Path "$rep\gaps.json")) { (Get-Content "$rep\gaps.json" -Raw | ConvertFrom-Json) | Where-Object { $_.note } | ForEach-Object { Add-Content $out "   note $($_.id): $($_.note)" } }
}
Add-Content $out "== done $(Get-Date -Format HH:mm:ss)"
