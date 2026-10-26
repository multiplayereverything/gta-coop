# Builds coop-dev\MISSIONS.md: every mission in scm/main.txt with
#  - coop port status (script calls Coop.EnableSyncingThisScript = ported upstream)
#  - features it uses that CoopAndreas does not sync yet (static scan of its script, see AGENTS.md sync backlog)
#  - the latest 4-player sweep result (testing\reports\sweep-*\missions.json, newest result per mission)
#
#   powershell -ExecutionPolicy Bypass -File testing\mission-catalog.ps1

$root = Split-Path -Parent $PSScriptRoot
$scm = Join-Path $root 'CoopAndreas\scm'
$out = Join-Path $root 'MISSIONS.md'

# feature -> regex over the mission script; all of these are unsynced or partly synced upstream
$features = [ordered]@{
    'pickups'      = 'Pickup\.Create'                    # pickups not synced
    'wanted'       = 'Player\.AlterWantedLevel'          # wanted level not synced
    'money'        = 'Player\.AddScore|Player\.IsScoreGreater'  # money not synced
    'fire'         = 'ScriptFire\.Create|Fire\.Create'   # fire not synced
    'trains'       = '\bTrain\.'                         # trains: no dedicated sync
    'trailers'     = 'Car\.AttachTrailer|AttachToCar'    # trailer sync missing
    'gang-group'   = 'Player\.SetGroupMember|Group\.'    # gang groups sync missing
    'gang-wars'    = '\bGang\.'                          # gang wars sync missing
    'checkpoints'  = 'Checkpoint\.Create'                # race checkpoints: only ported missions show them per player
    'parachute'    = 'Parachute|PARACHUTE'               # parachute sync missing
    'jetpack'      = 'Jetpack|JETPACK'                   # jetpack pickup sync missing
    'aircraft'     = 'Heli|Hunter|Maverick|Plane|Dodo|Shamal|Hydra|Rustler|Skimmer|Leviathn'
    'interiors'    = 'Streaming\.SetAreaVisible'
}

$ported = @{}
$readmePorted = @{}
Select-String -Path (Join-Path $root 'CoopAndreas\README.md') -Pattern '^- \[X\] (.+)$' -CaseSensitive:$false | ForEach-Object { $readmePorted[$_.Matches[0].Groups[1].Value.Trim()] = $true }

# newest sweep result per mission id
$sweep = @{}
$pass = @{}
Get-ChildItem (Join-Path $PSScriptRoot 'reports') -Directory -Filter 'sweep-*' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
    $f = Join-Path $_.FullName 'missions.json'
    if (Test-Path $f) {
        $data = Get-Content $f -Raw | ConvertFrom-Json   # PS 5 returns a JSON array as one object: assign, then loop
        # pass sweeps (-EndBy pass) are kept apart from the fail/death sweeps: a report with any pass result is one
        $isPass = @($data | Where-Object { $_.endedBy -like 'passed (*' -or $_.notes -like '*no debug pass*' }).Count -gt 0
        foreach ($r in $data) { if ($isPass) { $pass[[int]$r.id] = $r } else { $sweep[[int]$r.id] = $r } }
    }
}

$rows = @()
Select-String -Path (Join-Path $scm 'main.txt') -Pattern '^DEFINE MISSION (\d+) AT @(\w+)\s+//\s*(.*)$' | ForEach-Object {
    $g = $_.Matches[0].Groups
    $id = [int]$g[1].Value; $label = $g[2].Value; $name = $g[3].Value.Trim()
    $file = Join-Path $scm "scripts\$label.txt"
    $code = if (Test-Path $file) { Get-Content $file -Raw } else { '' }
    $isPorted = $code -match 'Coop\.EnableSyncingThisScript'
    $warn = $code -match 'currently unsupported'
    $tags = @($features.Keys | Where-Object { $code -match $features[$_] })
    $cut = ([regex]::Matches($code, 'Cutscene\.Load|load_cutscene')).Count
    $kind = if ($id -le 2) { 'setup' } elseif ($id -le 10) { 'minigame' } elseif ($id -le 112) { 'story' } else { 'side' }
    $s = $sweep[$id]
    $sweepText = if (-not $s) { 'not run' }
        elseif ($s.crash) { 'CRASH' }
        elseif (-not $s.started) { 'did not start' }
        elseif ($s.cutsceneStuck) { 'cutscene stuck' }
        elseif (-not $s.endedBy) { 'did not end' }
        elseif (-not ($s.botsSawStart -and $s.botsSawEnd)) { 'ok on host, partners missed start/end' }
        else { 'OK' }
    $ps = $pass[$id]
    $passText = if (-not $ps) { 'not run' }
        elseif ($ps.crash) { 'CRASH' }
        elseif ($ps.endedBy -like 'passed*') { if ($ps.botBanners -ge 1) { "PASSED, partners got the banner" } else { 'passed on host, partners missed the banner' } }
        else { 'no debug-pass check reached' }
    $rows += [pscustomobject]@{
        Pass = $passText
        Id = $id; Label = $label; Name = $name; Kind = $kind; Ported = $isPorted; Warn = $warn; Tags = $tags; Cutscenes = $cut
        Sweep = $sweepText; SweepDetail = if ($s) { "cutscenes $($s.cutscenesSkipped)/$(@($s.cutscenes).Count), partner texts $($s.botTexts), votes $($s.botVotes), banners $($s.botBanners)$(if ($s.botTeleports) { ", teleports $($s.botTeleports)" })" } else { '' }
        Crash = if ($s) { $s.crash } else { '' }
    }
}

$story = @($rows | Where-Object Kind -eq 'story')
$swept = @($story | Where-Object Sweep -ne 'not run')
$ok = @($swept | Where-Object Sweep -eq 'OK')
$passed = @($story | Where-Object { $_.Pass -like 'PASSED*' })
$passTried = @($story | Where-Object Pass -ne 'not run')

$md = @()
$md += '# Missions'
$md += ''
$md += "Generated by ``testing/mission-catalog.ps1`` on $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Re-run it after a sweep."
$md += ''
$md += '## How missions work in coop'
$md += '- The **host** (first player on the server) runs the mission script. Other players are partners.'
$md += '- **Ported** missions (upstream CoopAndreas) have per-player objectives, blips, checkpoints and teleports'
$md += '  (`Coop.*` commands in the script). The coop trigger needs **all players in the marker** for ported starts.'
$md += '- **Unported** missions show "This mission is currently unsupported" and run host-driven. Our fork adds a fallback'
$md += '  (`COpCodeSync.cpp` IsUnportedMissionFallbackOpcode): their texts, help, pass/fail banners, mission text table,'
$md += '  fades and cutscenes are sent to every player, so partners can follow along and vote to skip cutscenes.'
$md += '  Partner-specific objectives, blips that only show for the host, checkpoints and the features tagged below are not synced.'
$md += '- Cutscene skip is a vote: it needs **every** player (4/4).'
$md += ''
$md += '## Sweep summary (4 players: host + 3 bots, ``testing/mission-sweep.ps1``)'
$md += "- Story missions: $($story.Count). Swept: $($swept.Count). Clean (start, cutscenes skipped by vote, fail/pass, partners saw start+end, no crash): **$($ok.Count)**."
$md += "- Pass sweep (``-EndBy pass``: the mission's own pass routine via Rockstar's leftover debug skip, 4 players): tried $($passTried.Count), passed with the banner on all partners: **$($passed.Count)**."
$md += "- Ported upstream: $(@($story | Where-Object Ported).Count). Unported (host-driven + fallback): $(@($story | Where-Object { -not $_.Ported }).Count)."
$md += '- What the sweep checks: mission starts with 4 players, every cutscene is skippable by a 4/4 vote, the mission can end'
$md += '  (fail by host death), partners receive the on-mission start/end, texts and banners, no crash. The pass sweep runs'
$md += '  the mission''s real pass routine (rewards, register passed, next missions unlocked) instead of playing every objective;'
$md += '  playing the objectives with people is still the manual checklist below.'
$md += ''
$md += '## Feature tags (not synced or partly synced, see AGENTS.md "Sync backlog")'
$md += '`pickups` mission pickups exist only for the host | `wanted` wanted level is per player | `money` rewards/costs go to the host'
$md += '| `fire` script fires local | `trains` no train sync | `trailers` no trailer sync | `gang-group` recruits follow the host only'
$md += '| `gang-wars` territory wars unsynced | `checkpoints` race checkpoints host-only in unported missions | `parachute`, `jetpack`'
$md += '| `aircraft` flying works but is the least tested | `interiors` partners must enter the same interior themselves'
$md += ''
foreach ($kind in 'story', 'side', 'minigame', 'setup') {
    $md += "## $((Get-Culture).TextInfo.ToTitleCase($kind)) missions"
    $md += ''
    $md += '| # | Script | Mission | Coop port | Sweep (4 players) | Pass (own routine) | Details | Unsynced features |'
    $md += '|---|---|---|---|---|---|---|---|'
    foreach ($r in $rows | Where-Object Kind -eq $kind) {
        $port = if ($r.Ported) { 'ported' } else { 'unported (fallback)' }
        $md += "| $($r.Id) | $($r.Label) | $($r.Name) | $port | $($r.Sweep) | $($r.Pass) | $($r.SweepDetail) | $($r.Tags -join ', ') |"
    }
    $md += ''
}
$md += '## Manual playtest checklist per mission (needs people)'
$md += '1. All players stand in the marker (ported) or the host starts it (unported).'
$md += '2. Cutscene: everyone presses skip, the counter reaches N/N.'
$md += '3. Follow the objective text; check partners see the same objective.'
$md += '4. Finish it: MISSION PASSED banner shows for everyone, the next mission marker appears for everyone.'
$md += '5. Note anything from the feature tags that breaks, and add it to MODLOG.md + the sync backlog in AGENTS.md.'
$md | Set-Content $out -Encoding utf8
Write-Host "Wrote $out ($($rows.Count) missions; story swept $($swept.Count), clean $($ok.Count))"
