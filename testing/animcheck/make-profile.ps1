# Writes gtasa-profile.json for coop-anything's animcheck from plugin-sdk's ePedAnims.h (the ped/move animation
# table, ids 0-190, the same ids in every walking style group). Other groups seen in tests: 33 = jump, 49 = fists.
#   powershell -ExecutionPolicy Bypass -File testing\animcheck\make-profile.ps1
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$h = Join-Path $root 'CoopAndreas\third_party\plugin-sdk\plugin_sa\game_sa\ePedAnims.h'
$names = @([regex]::Matches((Get-Content $h -Raw), 'PED_ANIM_([A-Z0-9_]+)\s*=\s*0x([0-9A-F]+)') | ForEach-Object { @{ id = [Convert]::ToInt32($_.Groups[2].Value, 16); name = $_.Groups[1].Value } })
$groups = [ordered]@{}; foreach ($n in $names) { $groups["$($n.id)"] = $n.name }
$profile = [ordered]@{
    name = 'gta-sa'
    bones = [ordered]@{ root = 'pelvis'; left_upper_arm = 'upperarm_l'; left_hand = 'hand_l'; right_upper_arm = 'upperarm_r'; right_hand = 'hand_r' }
    groups = $groups
    categories = [ordered]@{ idle = @('ROADCROSS', 'GUN_STAND', 'GANG_GUNSTAND', 'WEAPON_CROUCH', 'SWIM_TREAD', 'XPRESSSCRATCH', 'SEAT_IDLE', 'CLIMB_IDLE', 'PHONE_TALK', 'ATM', 'DUCK_COWER', 'HANDSUP', 'HANDSCOWER'); walk = @('RUN_STOP', 'RUN_STOPR', 'GUNCROUCHFWD', 'GUNCROUCHBWD'); run = @('RUN_CIVI'); aim = @('GUN_2_IDLE', 'ARRESTGUN') }
    category_prefixes = [ordered]@{
        walk = @('WALK_', 'GUNMOVE_'); run = @('SPRINT_'); idle = @('IDLE_', 'FAC', 'ENDCHAT_', 'TAP_HAND'); dodge = @('CROUCH_ROLL_', 'EV_', 'FIGHTSH'); turn = @('TURN_')
        attack = @('49:', 'FIGHT2IDLE', 'BOMBER', 'SHOVE_'); hit = @('HIT_', 'SHOT_', 'DAM_', 'FLOOR_HIT', 'KD_', 'GETUP', 'GAS_CWR', 'FALL_COLLAPSE', 'FALL_BACK', 'FALL_FRONT')
        death = @('KO_', 'DROWN', 'CAR_DEAD_'); jump = @('33:', 'JUMP_', 'FALL_FALL', 'FALL_GLIDE', 'FALL_LAND', 'CLIMB_', 'ABSEIL', 'BIKE_FALL')
    }
    default_category = 'misc'
    angle_unit = 'rad'
    units_per_meter = 1.0
}
$out = Join-Path $PSScriptRoot 'gtasa-profile.json'
[IO.File]::WriteAllText($out, ($profile | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))  # no BOM: Python json rejects it
Write-Host "$out ($($names.Count) animations)"
