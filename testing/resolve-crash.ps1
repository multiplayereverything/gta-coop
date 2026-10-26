# Resolves CoopAndreasSA.dll+0xRVA offsets (from crash logs / CrashInfo dialogs) to function names
# using the linker map written by the client build (CoopAndreas/build/CoopAndreasSA.map).
# Only valid for the DLL built together with that map.
#
#   powershell -ExecutionPolicy Bypass -File testing\resolve-crash.ps1 0x505f0 0x2e9a3

param([Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Offsets)

$map = Join-Path (Split-Path -Parent $PSScriptRoot) 'CoopAndreas\build\CoopAndreasSA.map'
$base = 0x10000000
$symbols = foreach ($line in Get-Content $map) {
    # " 0001:000505e0       ?Foo@@YAXXZ                10051 5e0 f   obj.obj"
    if ($line -match '^\s*[0-9a-f]{4}:[0-9a-f]{8}\s+(\S+)\s+([0-9a-f]{8})\s+(f\s+)?(\S+)') {
        [pscustomobject]@{ Address = [Convert]::ToInt64($Matches[2], 16); Name = $Matches[1]; Object = $Matches[4] }
    }
}
$symbols = $symbols | Where-Object Address -gt 0 | Sort-Object Address

foreach ($o in $Offsets) {
    $target = $base + [Convert]::ToInt64(($o -replace '^0x', ''), 16)
    $best = $null
    foreach ($s in $symbols) { if ($s.Address -le $target) { $best = $s } else { break } }
    $name = $best.Name
    try { $name = (& undname.exe $best.Name 2>$null | Select-Object -Last 1) -replace '^is :- "|"$', '' } catch {}
    '{0} -> {1} +0x{2:X} ({3})' -f $o, $name, ($target - $best.Address), $best.Object
}
