# Playthrough: plays the first story missions (Big Smoke, Ryder) to MISSION PASSED with TWO real games (host +
# partner, like lab-duo.ps1), no pass shortcut. Each mission starts through its real marker (all players on foot in
# it), then a blip "autopilot" plays the objectives the way a player would:
#   - cutscenes: both vote to skip
#   - a blipped vehicle and the host on foot: get in (entermissioncar prefers the blipped one)
#   - a coord blip (destination / shop marker): go there (teleport, with the vehicle)
#   - blipped characters (Sweet, Ryder...): stay close behind them
#   - shop menus ("walk into the marker to buy"): press cross (buy) then triangle (leave)
# The partner acts on its own game: rides its own mission bike, and only catches up with the host when it falls
# behind or the host is in another interior (as a human would). Scripted teleports are checked: after every cutscene
# the partner's distance to the host is recorded BEFORE the autopilot moves anyone.
#
#   powershell -ExecutionPolicy Bypass -File testing\playthrough.ps1 [-Missions "11,12"] [-Minutes 10]
#
# Report: testing\reports\play-<time>\ (report.json, timeline-host.txt, timeline-partner.txt, autopilot.log).

param(
    [string]$Missions = '11,12',
    [int]$Minutes = 10,
    # missions to get through quickly with the debug pass (to iterate on a later mission); not a playthrough of them
    [string]$Shortcut = '',
    [int]$Port = 16790,
    [string]$GameDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'GTA San Andreas (test)')  # the test copy: never the game someone plays
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lab-common.ps1')

$report = Join-Path $PSScriptRoot ("reports\play-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
New-Item -ItemType Directory -Force $report | Out-Null
$script:ReportDir = $report
$apLog = Join-Path $report 'autopilot.log'
function Log($msg) { $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $msg; Add-Content $apLog $line; Write-Host "    $line" }

$PartnerDir = "$GameDir (partner)"
if (-not (Test-Path (Join-Path $PartnerDir 'gta_sa.exe'))) { throw "run testing\make-partner-copy.ps1 first" }
function GameDirOf($who) { if ($who -eq 'partner') { $PartnerDir } else { $GameDir } }
function AutoDir($who) { Join-Path (GameDirOf $who) "CoopAndreas\autotest\$who" }
function Events($who) {
    $p = Join-Path (AutoDir $who) 'events.jsonl'
    if (-not (Test-Path $p)) { return @() }
    @(Get-Content $p -ErrorAction SilentlyContinue | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
}
function Status($who) { try { Get-Content (Join-Path (AutoDir $who) 'status.json') -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null } }
function Cmd($who, $line) {
    $path = Join-Path (AutoDir $who) 'commands.txt'
    $bytes = [Text.Encoding]::ASCII.GetBytes($line + "`r`n")
    for ($i = 0; $i -lt 100; $i++) {
        try { $fs = [IO.File]::Open($path, 'Append', 'Write', 'ReadWrite, Delete'); try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }; return }
        catch { Start-Sleep -Milliseconds 50 }
    }
}
function WaitEv($who, [int]$from, [scriptblock]$cond, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    do {
        $all = Events $who
        for ($i = $from; $i -lt $all.Count; $i++) { if (& $cond $all[$i]) { return $all[$i] } }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $deadline)
    $null
}
function Count($who) { (Events $who).Count }
function Dist($a, $b) { [Math]::Sqrt([Math]::Pow($a.x - $b.x, 2) + [Math]::Pow($a.y - $b.y, 2) + [Math]::Pow($a.z - $b.z, 2)) }
function Timeline($who) {
    $all = Events $who; if ($all.Count -eq 0) { return }
    $s = $all[0].t
    $all | ForEach-Object { $rest = ($_.PSObject.Properties | Where-Object { $_.Name -notin 't', 'ev' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '; '{0,7:N1}s  {1,-22} {2}' -f (($_.t - $s) / 1000.0), $_.ev, $rest } |
        Set-Content (Join-Path $report "timeline-$who.txt") -Encoding utf8
}

# mission start markers (scm/scripts/INITIAL.txt $introX/$ryderX, triggered in INT.txt for ALL players on foot)
$markers = @{ 11 = @(2495.214, -1687.03, 13.5); 12 = @(2459.55, -1687.75, 13.6)
    # Sweet's house ($sweetX/Y/Z in INITIAL): his strand, one mission after another
    13 = @(2515.07, -1673.98, 13.2); 14 = @(2515.07, -1673.98, 13.2); 15 = @(2515.07, -1673.98, 13.2) }
$names = @{ 11 = 'Big Smoke'; 12 = 'Ryder'; 13 = 'Tagging Up Turf'; 14 = 'Cleaning The Hood'; 15 = 'Drive-Thru' }

$names = @{ 11 = 'Big Smoke'; 12 = 'Ryder'; 13 = 'Tagging Up Turf'; 14 = 'Cleaning The Hood'; 15 = 'Drive-Thru' }
Start-Sleep 1
foreach ($w in 'host', 'partner') { New-Item -ItemType Directory -Force (AutoDir $w) | Out-Null; Remove-Item "$(AutoDir $w)\*" -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue }
$crashDirs = @($LabCrashDir, (Join-Path $PartnerDir 'CoopAndreas_crashes'))
$crashes0 = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count

$work = Join-Path $env:TEMP "coopandreas-play-$Port"
New-Item -ItemType Directory -Force $work | Out-Null
Get-Process server -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$work*" } | Stop-Process -Force   # left from a killed run
Start-Sleep 1
Copy-Item (Join-Path $LabBin 'server.exe') $work -Force
Set-Content (Join-Path $work 'server-config.ini') "port = $Port`nmaxplayers = 4`n" -Encoding ascii
$server = Start-Process (Join-Path $work 'server.exe') -WorkingDirectory $work -PassThru -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $report 'server.log') -RedirectStandardError (Join-Path $report 'server.err')

function StartGame($who) {
    $dir = GameDirOf $who
    Start-Process (Join-Path $dir 'gta_sa.exe') -WorkingDirectory $dir -PassThru `
        -ArgumentList "--coop --autotest $LabHideArg -autoip 127.0.0.1 -autoport $Port -autoname $who -autodir $who"
}

# one autopilot tick for the host: returns a short description of what it did
$script:lastTarget = $null
$script:shopStep = 0
function HostTick($hs) {
    if ($hs.cutscene) { return 'cutscene' }
    $me = $hs.local
    # inside a shop with the controls locked = its menu (barber chair, food counter): buy, then leave the menu
    # widescreen, or controls locked outside a shop menu = a scripted scene is running: hands off
    if ($hs.widescreen -or ($hs.controlsDisabled -and $me.interior -eq 0)) { return 'scripted (controls locked)' }
    # (triangle leaves the whole shop, so only after something was bought or after 30 s)
    if ($hs.controlsDisabled -and $me.interior -ne 0) {
        # already bought and left the menu: the stand-up / leave animation runs with locked controls - wait
        # (an exit press during the haircut/eating animation is ignored: repeat it, never buy again)
        if ($script:leaveShop) {
            $script:menuStep++
            if ($script:menuStep % 3 -eq 0) { Cmd 'host' 'press triangle 250'; return 'leaving the shop menu: press triangle' }
            return 'leaving the shop menu (controls locked)'
        }
        if (-not $script:menuSince) { $script:menuSince = Get-Date; $script:menuMoney = $me.money }
        $script:menuStep++
        $bought = $me.money -ne $script:menuMoney
        if (($bought -or ((Get-Date) - $script:menuSince).TotalSeconds -gt 30) -and $script:menuStep % 3 -eq 0) {
            if ($bought) { $script:leaveShop = $true }
            Cmd 'host' 'press triangle 250'; return "shop menu: press triangle (leave, bought=$bought)"
        }
        if (-not $bought -and $script:menuStep % 3 -eq 1) { Cmd 'host' 'press cross 250'; return 'shop menu: press cross (buy)' }
        return "shop menu (money $($script:menuMoney) -> $($me.money))"
    }
    $script:menuSince = $null
    # just came out of a shop: stay on foot by the door for a bit (the scripts check "on foot near the shop")
    if ($script:leftShopAt -and ((Get-Date) - $script:leftShopAt).TotalSeconds -lt 12) { return 'outside the shop, waiting on foot' }
    # bought what the mission wanted: walk back out through the shop door (the coop scripts continue outside)
    if ($script:leaveShop) {
        if ($me.interior -eq 0 -and $me.z -lt 500) {
            # out: step off the door spot (standing on it walks you straight back in), towards the mission vehicle
            $script:leaveShop = $false; $script:leftShopAt = Get-Date
            $car = @(@($hs.blips) | Where-Object type -eq 1) | Sort-Object { Dist $me $_ } | Select-Object -First 1
            if ($car) { Cmd 'host' ("walkto {0:F2} {1:F2} {2:F2}" -f $car.x, $car.y, $car.z) }
            else { Cmd 'host' ("walkto {0:F2} {1:F2} {2:F2}" -f ($me.x + 4), ($me.y - 3), $me.z) }
            return 'out of the shop: step away from the door'
        }
        elseif ($me.interior -eq 0) { return 'leaving the shop: exit transition' }   # area switched, position not yet
        else {
            $door = @($hs.doors) | Where-Object { $_.area -eq $me.interior } | Sort-Object { Dist $me $_ } | Select-Object -First 1
            if (-not $door) { return 'leaving the shop: no door within 40 m' }
            if ((Dist $me $door) -gt 1.5) { Cmd 'host' ("teleport {0:F2} {1:F2} {2:F2}" -f $door.x, $door.y, ($door.z + 0.6)); return "leave the shop through door $($door.name)" }
            return "in door $($door.name), leaving"
        }
    }
    $blips = @($hs.blips)
    $coord = @($blips | Where-Object type -eq 4)
    $cars = @($blips | Where-Object type -eq 1)
    $chars = @($blips | Where-Object type -eq 2)
    $script:hostInMarker = $false
    # destination: a drawn marker (locate "go here" cylinders, shop/entry markers) or a coord blip
    # (the game keeps markers of other areas in its list: only those on our side of the doors)
    $inside = $me.interior -ne 0 -or $me.z -gt 500
    $marks = @(@($hs.markers) | Where-Object { $_.type -eq 1 -and ($_.z -gt 500) -eq $inside -and [Math]::Abs($_.x) + [Math]::Abs($_.y) -gt 1 })
    $dest = @($marks) + @($coord) | Sort-Object { Dist $me $_ } | Select-Object -First 1
    # a coord blip with a drawn marker on it: use the marker (it has a size: small ones are walk-in shop markers)
    if ($dest -and $dest.type -eq 4) { $onIt = @($marks) | Where-Object { (Dist $_ $dest) -lt 3 } | Select-Object -First 1; if ($onIt) { $dest = $onIt } }
    # a blipped character (Ryder, Sweet) has to come along: escort it until it is near the destination - the script
    # freezes AI riders nobody is near, and the finish usually needs them there too
    $escort = $chars | Sort-Object { Dist $me $_ } | Select-Object -First 1
    if ($dest -and $escort -and (Dist $escort $dest) -gt 50) { $dest = $null }
    # just finished a shop: its blip stays until the script's "outside the shop" scene (which waits for the partners
    # to come out too) - wait outside instead of walking back in
    if ($dest -and $dest.z -gt 500 -and $me.interior -eq 0 -and $script:leftShopAt -and ((Get-Date) - $script:leftShopAt).TotalSeconds -lt 60) {
        return 'done in the shop: waiting outside for everyone'
    }
    # a destination on the other side of a door (shops: z ~1000 inside, back outside afterwards) is reached by walking
    # into the door's entry/exit marker, like a player does
    if ($dest -and (($dest.z -gt 500) -ne ($me.interior -ne 0))) {
        # going in: the door on our side that leads closest to the destination; going out: the nearest door
        $side = @($hs.doors) | Where-Object { ($_.z -gt 500) -eq $inside }
        $door = if ($dest.z -gt 500) { $side | Sort-Object { [Math]::Sqrt([Math]::Pow($_.tx - $dest.x, 2) + [Math]::Pow($_.ty - $dest.y, 2)) } | Select-Object -First 1 }
                else { $side | Sort-Object { Dist $me $_ } | Select-Object -First 1 }
        if (-not $door) { return 'destination behind a door, no door within 300 m' }
        if ($me.inVehicle) { Cmd 'host' 'leavevehicle'; return 'get out to walk through the door' }
        if ((Dist $me $door) -gt 1.5) { Cmd 'host' ("teleport {0:F2} {1:F2} {2:F2}" -f $door.x, $door.y, ($door.z + 0.6)); return "walk into door $($door.name)" }
        return "in door $($door.name), waiting"
    }
    # Tagging Up Turf: spray every rival tag near you BEFORE getting back in the car (the "get in the blipped car" rule
    # came first and left tags behind: the mission waited). spraytag paints the nearest unsprayed tag within 100 m (out
    # of the car if needed) and shares it like a real spray; none near: follow the car and blips to the next area.
    if ($hs.mission -eq 'sweet1' -and (-not $script:noTagUntil -or (Get-Date) -gt $script:noTagUntil)) {
        $f = Count 'host'; Cmd 'host' 'spraytag'
        $ev = WaitEv 'host' $f { param($x) $x.ev -eq 'command' -and $x.cmd -eq 'spraytag' } 5
        if ($ev -and $ev.result -ne 'none') { $script:noTagUntil = $null; return "spray tag at $($ev.result)" }
        $script:noTagUntil = (Get-Date).AddSeconds(8)
    }
    # a blipped vehicle and on foot: get in first (the objective vehicle keeps its blip while you walk into a shop)
    # 400 m: after the last tags in an area Sweet's car was 140 m away and the host stood still
    $nearCars = @($cars | Where-Object { (Dist $me $_) -lt 400 })
    if (-not $me.inVehicle -and $nearCars.Count -gt 0) { Cmd 'host' 'entermissioncar'; return 'enter blipped vehicle' }
    # just got into a vehicle: give mission characters (Ryder) time to climb in before driving off
    $twoWheels = 448, 461, 462, 463, 468, 471, 481, 509, 510, 521, 522, 523, 581, 586
    if ($me.inVehicle -and $twoWheels -notcontains $me.vehicleModel) {   # bikes: nobody climbs in, and the riders leave
        if (-not $script:inVehSince) { $script:inVehSince = Get-Date }
        # long enough for a walking mission character (Ryder took over 8 s once and was left behind: mission stuck)
        if (((Get-Date) - $script:inVehSince).TotalSeconds -lt 20) { return 'in the vehicle, waiting for passengers' }
    }
    else { $script:inVehSince = $null }
    # a far destination on foot: a player would take the vehicle the mission is about to blip (Ryder's car) -
    # give the script a few seconds to show it before going on foot
    if ($dest -and -not $me.inVehicle -and (Dist $me $dest) -gt 150) {
        if (-not $script:farSince) { $script:farSince = Get-Date }
        if (((Get-Date) - $script:farSince).TotalSeconds -lt 10) { return 'far destination: waiting for a vehicle objective' }
    }
    else { $script:farSince = $null }
    if ($dest) {
        $t = $dest
        $d = Dist $me $t
        # a coord blip inside a shop marks a walk-in marker; the shop script only draws (and accepts) it after the
        # player has stepped off the spot, so step off and come back walking
        if ($t.type -eq 4 -and $t.z -gt 500 -and -not (@($marks) | Where-Object { (Dist $_ $t) -lt 3 })) {
            if ($d -lt 3) { Cmd 'host' ("walkto {0:F2} {1:F2} {2:F2}" -f ($t.x + 3.5), $t.y, $t.z); return 'step off the shop spot (marker hidden)' }
            return 'waiting for the shop marker'
        }
        # small markers (shops, size ~1) need a player who walked in and stopped: get near, then walk onto it
        $small = $t.PSObject.Properties['size'] -and $t.size -lt 1.5 -and -not $me.inVehicle
        if ($small -and $d -gt 0.7) {
            if ($d -gt 4) { Cmd 'host' ("teleport {0:F2} {1:F2} {2:F2}" -f ($t.x + 2.5), $t.y, ($t.z + 1.0)); return 'near a shop marker' }
            Cmd 'host' ("walkto {0:F2} {1:F2} {2:F2}" -f $t.x, $t.y, $t.z); return ("walk onto the marker ({0:F1} m)" -f $d)
        }
        if (-not $small -and $d -gt 2.5) { Cmd 'host' ("teleport {0:F2} {1:F2} {2:F2}" -f $t.x, $t.y, ($t.z + 0.5)); return ("to coord blip {0:F0},{1:F0} ({2:F0} m)" -f $t.x, $t.y, $d) }
        # standing in a marker: shop menus need a button (buy, then leave); harmless elsewhere
        $script:hostInMarker = $true
        return 'in marker, waiting'
    }
    # 3. blipped characters: stay close behind the nearest one
    if ($chars.Count -gt 0) {
        $t = $chars | Sort-Object { Dist $me $_ } | Select-Object -First 1
        $d = Dist $me $t
        if ($d -gt 8) {
            $dx = 0; $dy = -5
            if ($script:lastTarget) { $vx = $t.x - $script:lastTarget.x; $vy = $t.y - $script:lastTarget.y; $len = [Math]::Sqrt($vx * $vx + $vy * $vy); if ($len -gt 0.5) { $dx = -6 * $vx / $len; $dy = -6 * $vy / $len } }
            $script:lastTarget = $t
            Cmd 'host' ("teleport {0:F2} {1:F2} {2:F2}" -f ($t.x + $dx), ($t.y + $dy), ($t.z + 1.0))
            return ("follow blipped char ({0:F0} m)" -f $d)
        }
        $script:lastTarget = $t
        return 'close to blipped char'
    }
    return 'nothing to do'
}

function PartnerTick($ps, $hs) {
    if (-not $ps -or -not $hs -or $ps.cutscene) { return 'cutscene' }
    # the host's scripted scene (or shop menu): the script places the partner too, don't move
    if ($hs.widescreen -or $hs.controlsDisabled -or $ps.controlsDisabled) { return 'scripted (controls locked)' }
    $hostP = $ps.players | Where-Object name -eq 'host' | Select-Object -First 1   # remote players' isHost isn't set on partners
    if (-not $hostP -or -not $hostP.hasPed) { return 'no host ped' }
    # the host's area from its own game (a remote ped's area code isn't kept current on the partner)
    $hostArea = $hs.local.interior
    $hostP = [pscustomobject]@{ x = $hs.local.x; y = $hs.local.y; z = $hs.local.z; interior = $hostArea }
    if ($hostArea -eq $ps.local.interior) { $script:partnerDoorTries = 0 }
    if ($hostArea -ge 0 -and $hostArea -ne $ps.local.interior) {
        # walk through the same door when it is near (as a player does); otherwise jump to the host's area
        $door = @($ps.doors) | Where-Object { $_.area -eq $ps.local.interior } | Sort-Object { Dist $ps.local $_ } | Select-Object -First 1
        $script:partnerDoorTries++
        if ($door -and $script:partnerDoorTries -le 2) {
            if ($ps.local.inVehicle) { Cmd 'partner' 'leavevehicle'; return 'get out to walk through the door' }
            Cmd 'partner' ("teleport {0:F2} {1:F2} {2:F2}" -f $door.x, $door.y, ($door.z + 0.6))
            return "follow host through door $($door.name)"
        }
        Cmd 'partner' "interior $($hostP.interior)"
        Cmd 'partner' ("teleport {0:F2} {1:F2} {2:F2}" -f ($hostP.x + 1.5), $hostP.y, ($hostP.z + 0.5))
        return "jump into the host's interior $($hostP.interior)"
    }
    # (a partner CAR teleported onto the host's car wrecked both: cars park beside it; on foot / bikes join exactly)
    $bikes = 448, 461, 462, 463, 468, 471, 481, 509, 510, 521, 522, 523, 581, 586
    $carSize = $ps.local.inVehicle -and $bikes -notcontains $ps.local.vehicleModel
    $joinOff = if ($carSize) { 3.5 } else { 0.8 }
    if ($script:hostInMarker -and (Dist $ps.local $hostP) -gt ($joinOff + 1)) {
        Cmd 'partner' ("teleport {0:F2} {1:F2} {2:F2}" -f ($hostP.x + $joinOff), ($hostP.y + 0.6), ($hostP.z + 0.5))
        return 'join the host in the marker'
    }
    # vehicles: the host takes the objective vehicle first (it has to drive it); the partner then rides along as the
    # host's passenger, or takes its own mission vehicle when the host's has no free seat (bikes)
    if (-not $ps.local.inVehicle -and $hs.local.inVehicle) {
        # too far to get in anything near the host (Tagging Up Turf: 40 m away, trying forever): go there first
        $dh = Dist $ps.local $hostP
        if ($dh -gt 15) { Cmd 'partner' ("teleport {0:F2} {1:F2} {2:F2}" -f ($hostP.x + 3), ($hostP.y + 3), ($hostP.z + 1.0)); return ("go to the host's vehicle ({0:F0} m)" -f $dh) }
        $script:partnerVehTry++
        # its OWN vehicle first (the one blipped on its screen: the coop scripts give partners their own Greenwood/BMX;
        # the host's passenger seat may be the mission character's - Ryder can't get in if a partner sits there)
        # any free mission vehicle nearby (own Greenwood, the extra copy the coop mod spawns); the host's passenger seat
        # only as a last resort
        if ($script:partnerVehTry % 4 -ne 0) { Cmd 'partner' 'entermissioncar'; return 'get in a free mission vehicle' }
        Cmd 'partner' 'enterpassenger'; return 'ride along as the host''s passenger'
    }
    if (-not $hs.local.inVehicle -and $ps.local.inVehicle) { Cmd 'partner' 'leavevehicle'; return 'leave vehicle like the host' }
    # the partner gets the same "follow Sweet/Ryder" blips: stay close behind the nearest one, like the host does
    $chars = @(@($ps.blips) | Where-Object type -eq 2)
    if ($chars.Count -gt 0) {
        $t = $chars | Sort-Object { Dist $ps.local $_ } | Select-Object -First 1
        $dc = Dist $ps.local $t
        if ($dc -gt 7) { Cmd 'partner' ("teleport {0:F2} {1:F2} {2:F2}" -f ($t.x + 2.5), ($t.y + 2.5), ($t.z + 1.0)); return ("follow blipped char ({0:F0} m)" -f $dc) }
        return ("near blipped char ({0:F0} m)" -f $dc)
    }
    $d = Dist $ps.local $hostP
    $off = if ($ps.local.inVehicle) { 7 } else { 3 }   # cars need room: stacked on the host's car they wreck each other
    # a moved bike throws its rider off (the game's way): the partner walked back to its own bike 140 m away and
    # caught up again forever (Big Smoke). Get off, catch up on foot, then take a free mission bike near the host.
    $bikes = 448, 461, 462, 463, 468, 471, 481, 509, 510, 521, 522, 523, 581, 586
    # the partner's own copy of a ported mission puts it back on ITS bike (a player would ride it): move the bike with
    # the rider on it the way a script places a car (carto = set_car_coordinates keeps the rider seated)
    if ($d -gt 15 -and $ps.local.inVehicle -and $bikes -contains [int]$ps.local.vehicleModel) {
        Cmd 'partner' ("carto {0:F2} {1:F2} {2:F2} 0" -f ($hostP.x + 4), ($hostP.y + 4), ($hostP.z + 0.5))
        return ("ride the bike to the host ({0:F0} m)" -f $d)
    }
    if ($d -gt 15) { Cmd 'partner' ("teleport {0:F2} {1:F2} {2:F2}" -f ($hostP.x + $off), ($hostP.y + $off), ($hostP.z + 1.0)); return ("catch up with host ({0:F0} m)" -f $d) }
    return ("near host ({0:F0} m)" -f $d)
}

# What a player does between missions to unlock the next one (the game's own hint text says so).
# After Big Smoke: "Go inside CJ's house to continue." (INTROST: area 3 at the save point, then back outside on
# Grove Street restarts the INT trigger and adds Ryder's blip).
function EnterNearestMarker($who, [double]$x, [double]$y, [double]$z, [int]$area) {
    Cmd $who ("teleport {0} {1} {2}" -f $x, $y, $z)
    Start-Sleep 2
    $s = Status $who
    Log ("{0} near the door at {1:F1},{2:F1},{3:F1}; doors: {4}" -f $who, $s.local.x, $s.local.y, $s.local.z, ((@($s.doors) | ForEach-Object { '{0}(area {1})@{2:F1},{3:F1},{4:F1}' -f $_.name, $_.area, $_.x, $_.y, $_.z }) -join ' '))
    $m = @($s.doors) | Sort-Object { Dist $s.local $_ } | Select-Object -First 1
    if ($m -and (Dist $s.local $m) -lt 15) { Cmd $who ("teleport {0:F2} {1:F2} {2:F2}" -f $m.x, $m.y, ($m.z + 0.6)) }
    $deadline = (Get-Date).AddSeconds(12)
    while ((Get-Date) -lt $deadline) { if ((Status $who).local.interior -eq $area) { return 'marker' }; Start-Sleep -Milliseconds 500 }
    return 'not entered'
}
function BetweenMissions([int]$after) {
    if ($after -ne 11) { return }
    foreach ($w in 'host', 'partner') { if ((Status $w).local.inVehicle) { Cmd $w 'leavevehicle' } }
    Start-Sleep 2
    $r = EnterNearestMarker 'host' 2495.3 -1690.0 13.8 3
    Log "host enters CJ's house through the door marker: $r"
    Check "After Big Smoke: CJ's house door takes the host inside (interior 3)" ($r -eq 'marker') ''
    if ($r -ne 'marker') { Cmd 'host' 'interior 3' }
    # the partner follows the host inside the same way
    $rp = EnterNearestMarker 'partner' 2495.6 -1690.0 13.8 3
    Log "partner enters CJ's house through the door marker: $rp"
    Check "After Big Smoke: the partner can follow into CJ's house" ($rp -eq 'marker') ''
    Cmd 'host' 'teleport 2496.05 -1698.0 1014.75'     # the save point the tutorial waits for
    Start-Sleep 7
    $s = Status 'host'
    $exit = @($s.doors) | Sort-Object { Dist $s.local $_ } | Select-Object -First 1
    Log ("host inside at {0:F1},{1:F1},{2:F1} area {3}; exit door: {4}" -f $s.local.x, $s.local.y, $s.local.z, $s.local.interior, $(if ($exit) { "$($exit.name)@$([int]$exit.x),$([int]$exit.y),$([int]$exit.z)" } else { 'none' }))
    if ($exit) { Cmd 'host' ("teleport {0:F2} {1:F2} {2:F2}" -f $exit.x, $exit.y, ($exit.z + 0.6)) }
    $deadline = (Get-Date).AddSeconds(12); $out = $false
    while ((Get-Date) -lt $deadline -and -not $out) { $out = (Status 'host').local.interior -eq 0; Start-Sleep -Milliseconds 500 }
    Check "After Big Smoke: the host walks back out through the exit marker" $out ''
    if (-not $out) { Cmd 'host' 'interior 0'; Cmd 'host' 'teleport 2495.3 -1689.2 13.4' }
    Start-Sleep 2
    Cmd 'host' 'teleport 2495.3 -1689.2 13.4'
    $ps = Status 'partner'
    if ($ps.local.interior -ne 0) { Cmd 'partner' 'interior 0'; Cmd 'partner' 'teleport 2496.3 -1689.2 13.4' }
    Start-Sleep 8
}

$host_ = $null; $partner = $null
try {
    $host_ = StartGame 'host'
    $e = WaitEv 'host' 0 { param($x) $x.ev -eq 'host_gained' } 90
    Check 'Host game connects and hosts' ([bool]$e) ''
    if (-not $e) { throw 'host failed' }
    Start-Sleep 15
    $partner = StartGame 'partner'
    $e = WaitEv 'partner' 0 { param($x) $x.ev -eq 'authenticated' } 90
    Check 'Partner game connects' ([bool]$e) ''
    if (-not $e) { throw 'partner failed' }
    Start-Sleep 15

    foreach ($id in ($Missions -split ',' | ForEach-Object { [int]$_ })) {
        $name = $names[$id]
        Write-Host "== $id $name"
        $m = $markers[$id]
        $hf = Count 'host'; $pf = Count 'partner'
        # wait for the mission marker to be active (previous mission's aftermath, INT's wait time)
        $started = $null
        for ($try = 0; $try -lt 12 -and -not $started; $try++) {
            foreach ($w in 'host', 'partner') { if ((Status $w).local.inVehicle) { Cmd $w 'leavevehicle' } }
            Start-Sleep 1
            Cmd 'host' ("teleport {0} {1} {2}" -f $m[0], $m[1], $m[2])
            Cmd 'partner' ("teleport {0} {1} {2}" -f ($m[0] + 0.4), ($m[1] + 0.3), $m[2])
            $started = WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_started' } 10
        }
        Check "$name starts from its marker with both players on foot in it" ([bool]$started) ''
        if (-not $started) { continue }
        $pstart = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_started' } 10
        Check "$name - partner gets on-mission" ([bool]$pstart) ''

        $deadline = (Get-Date).AddMinutes($Minutes)
        if (($Shortcut -split ',') -contains "$id") { Start-Sleep 8; Cmd 'host' 'skipcutscene'; Cmd 'partner' 'skipcutscene'; Start-Sleep 3; Cmd 'host' 'passmission'; Log "${name}: shortcut (passmission)" }
        $result = $null; $scene = $false; $script:hostInMarker = $false; $script:leaveShop = $false; $lastAction = ''; $lastTrace = Get-Date; $lastCut = 'start'; $lastP = ''; $seenCut = @{}; $teleportChecks = @()
        $hostCount = $hf
        while ((Get-Date) -lt $deadline -and -not $result) {
            if ($host_.HasExited -or $partner.HasExited) { break }
            $hs = Status 'host'; $ps = Status 'partner'
            $hev = Events 'host'
            for ($i = $hostCount; $i -lt $hev.Count; $i++) {
                $x = $hev[$i]
                if ($x.ev -eq 'cutscene_started') { Log "cutscene $($x.name)"; $lastCut = $x.name }
                if ($x.ev -eq 'players_hidden') { $scene = $true }
                if ($x.ev -eq 'players_shown') {
                    $scene = $false
                    # scripted teleports: when a cutscene / scripted scene ends (other CJs shown again) the script has
                    # placed every player; measure before the autopilot moves anyone
                    Start-Sleep 2
                    $h2 = Status 'host'; $p2 = Status 'partner'
                    $hp = $p2.players | Where-Object name -eq 'host' | Select-Object -First 1
                    if ($h2 -and $p2 -and $hp) {
                        $d = Dist $p2.local $hp
                        $teleportChecks += [pscustomobject]@{ after = $lastCut; distance = [Math]::Round($d, 1); host = "$([int]$h2.local.x),$([int]$h2.local.y)"; partner = "$([int]$p2.local.x),$([int]$p2.local.y)" }
                        Log ("after cutscene: partner {0:F1} m from host (host {1:F0},{2:F0} partner {3:F0},{4:F0})" -f $d, $h2.local.x, $h2.local.y, $p2.local.x, $p2.local.y)
                    }
                }
                if ($x.ev -eq 'mission_passed' -or $x.ev -eq 'mission_failed') { $result = $x }
            }
            $hostCount = $hev.Count
            if ($result) { break }
            if ($hs.cutscene -and -not $seenCut[$hs.cutscene]) { $seenCut[$hs.cutscene] = $true; Cmd 'partner' 'skipcutscene'; Cmd 'host' 'skipcutscene' }
            elseif ($hs.cutscene) { Cmd 'partner' 'skipcutscene'; Cmd 'host' 'skipcutscene' }
            # nobody moves during a scripted scene (the script is placing the players)
            $a = if ($scene) { 'scripted scene' } else { HostTick $hs }
            if ($a -ne $lastAction) { Log "host: $a"; $lastAction = $a }
            $b = if ($scene) { 'scripted scene' } else { PartnerTick $ps $hs }
            if ($b -notlike 'near *' -and $b -notlike 'follow blipped*' -and $b -ne $lastP) { Log "partner: $b" }
            $lastP = $b
            if (((Get-Date) - $lastTrace).TotalSeconds -ge 10) {
                $lastTrace = Get-Date
                $bl = ((@($hs.blips) | ForEach-Object { '{0}/{1}@{2:F0},{3:F0}' -f $_.type, $_.colour, $_.x, $_.y }) +
                    (@($hs.markers) | ForEach-Object { 'marker{0}@{1:F0},{2:F0}' -f $_.type, $_.x, $_.y })) -join ' '
                Log ("trace host {0:F0},{1:F0},{2:F0} veh={3} | partner {4:F0},{5:F0} veh={6} | blips {7}" -f $hs.local.x, $hs.local.y, $hs.local.z, $hs.local.vehicleModel, $ps.local.x, $ps.local.y, $ps.local.vehicleModel, $bl)
            }
            Start-Sleep -Milliseconds 1200
        }
        $passed = $result -and $result.ev -eq 'mission_passed'
        Check $(if (($Shortcut -split ',') -contains "$id") { "$name passed via the debug-pass shortcut" } else { "$name played to MISSION PASSED (no shortcut)" }) ([bool]$passed) $(if ($result) { "$($result.ev) gxt=$($result.gxt)" } else { "timed out after $Minutes min; last: $lastAction" })
        $pp = WaitEv 'partner' $pf { param($x) $x.ev -eq 'mission_passed' } 20
        if ($passed) { Check "$name - partner sees MISSION PASSED" ([bool]$pp) '' }
        $far = @($teleportChecks | Where-Object { $_.distance -gt 25 })
        Check "$name - scripted teleports keep the partner with the host (after each cutscene)" ($teleportChecks.Count -gt 0 -and $far.Count -eq 0) (($teleportChecks | ForEach-Object { "$($_.after): $($_.distance) m" }) -join '; ')
        WaitEv 'host' $hf { param($x) $x.ev -eq 'mission_ended' } 20 | Out-Null
        Start-Sleep 8
        if ($passed) { BetweenMissions $id }
    }
}
catch { Check 'Playthrough run' $false $_.Exception.Message }
finally {
    $new = @(Get-ChildItem $crashDirs -Filter *.log -ErrorAction SilentlyContinue).Count - $crashes0
    Check 'No new crash logs' ($new -le 0) "$new"
    Timeline 'host'; Timeline 'partner'
    foreach ($g in $host_, $partner) { if ($g -and -not $g.HasExited) { Stop-Process -Id $g.Id -Force } }
    if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
$failed = @($LabResults | Where-Object { -not $_.pass }).Count
$LabResults | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $report 'report.json') -Encoding utf8
Write-Host ("{0} passed, {1} failed. Report: {2}" -f ($LabResults.Count - $failed), $failed, $report)
exit $failed
