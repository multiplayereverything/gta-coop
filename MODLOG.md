# MODLOG

Newest first. Every change to the game folder or the CoopAndreas fork goes here.

## 2026-10-26 (night): playtest kit, real playthroughs, test safety (ef1a3e0..78168c2)
- Playtest kit for real sessions: `/report <text>` in the chat writes `CoopAndreas_reports\report-<time>.txt`
  (mission, place, players, ping/loss, newest crash log; nothing is sent). The server tells everyone when a player
  has been silent at the network level for 5 s (PLAYER_CONNECTION_STATE; a paused game still answers) and their name
  tag says "(connection lost)". rejoin.ps1 8/8; chaos-test bad_wifi + hell: only the deliberate 10 s outage flags it.
- Real playthrough (playthrough.ps1, no pass shortcut) on today's build: Big Smoke + Ryder 16/16. Autopilot: a bike
  is moved with its rider (carto), the host waits 20 s for mission passengers (Ryder was left behind once), the partner
  goes to the host's vehicle before trying to get in, Tagging Up Turf sprays tags (`spraytag`) and gets out at tag
  areas. Missions 13-15 added to its start-marker table (Sweet's house).
- MISTAKE: playthrough.ps1 still defaulted to the real game folder and ran there 3 times (old build there, results
  invalid; only cleo/modloader logs and CoopAndreas\autotest\host files written; Documents unchanged). All test
  runners now default to the "(test)" copy and lab-common.ps1 refuses the real folder unless `$AllowRealGame` is set
  (crash-test.ps1 only).
- Real playthrough now reaches 3 story missions: Big Smoke, Ryder and Tagging Up Turf all played to MISSION PASSED
  on both games (20/21; the miss is the "partner near the host after each scene" check when the autopilot jumped to a
  far tag just before a short tag camera scene). Found on the way: the partner vehicle copies had a blue "friendly"
  blip like the mission car, so the host could take the copy and the mission waited for its own car; copies are green
  now (CMissionPartnerVehicles::IsExtraVehicle for the autotest).
- Minigames: not automated (most are locked by story progress; each player's own game runs them).
- Note: the upstream CCrashReporter uploads crash logs to the CoopAndreas author's server (said in friend-README).

## 2026-10-26 (later): collectibles, rejoin, research (3a8d9c2..b5e7a04)
- Collectibles (CCollectibleSync, new packet COLLECTIBLE_COLLECTED, server relays it): an oyster, horseshoe or
  snapshot one player finds is removed for everyone and counted on every game (stat +1), so the COLLS rewards count
  all finds. collectibles.ps1 14/14 (host and partner collecting).
- Rejoin (rejoin.ps1): a player whose game was closed hard can join again at once (the server ends their silent old
  session for the same name and address, idea from the CoopAndreas-DE crash-fix list); the host repeats the
  on-mission flag every 5 s so a mid-mission joiner is in the mission. Known: until then the host shows the closed
  player for up to 30-60 s.
- Gang recruits (gang-recruits.ps1): a member recruited by the host or by a partner stands by and follows that player
  on both screens.
- All story missions with 2 players: 101/102 pass, no crash (MISSIONS.md).
- /coop-research: 5 more San Andreas co-op projects found (SA:COOP, CoopAndreas-remaster, CoopAndreas-DE and other
  forks, gtco-op sa-coop, a split-screen mod); toolkit directory corrected on a local branch (not published).
- 4-player sweep (host + 3 bots, all 102 story missions): every mission starts and ends for all four. Fixed:
  - crash after ~70 missions in one session: the vehicle struct pool (127, set by CPatch; streaming keeps up to 127
    vehicle models) was full -> CVehicleModelInfo::PreprocessHierarchy wrote through null. Pool now 500 (the pool
    constructor call at 0x5B8FE7 is wrapped; status `pools.vehicleStruct/Size`).
  - opening cutscenes of New Model Army and Up, Up and Away! never ended: the game checks the skip button only while
    the cutscene's fly-by camera runs (0x5B1901: active cam mode 17, load status 2, >1 s left). A failed mission left a
    scripted camera (RC plane in Supply Lines): it is now handed back 1 s after a mission ends and before a cutscene
    starts. New Model Army's cutscene camera still leaves within a second after Supply Lines (cause not found), so a
    cutscene whose camera is off fly-by for 3 s is finished like a skip (`cutscene_unstuck` event).
- Session logs go to the owner's Discord through `testing/post-discord.ps1` (webhook in `.discord-webhook`, a secret:
  never commit or print it).

## 2026-10-26: coop-anything toolkit adopted; network, animation and user-track fixes (d74c991..7b0565c)
- Toolkit: https://github.com/cranebeaker/coop-anything cloned to `toolkit-coop-anything/` (playbooks, chaos relay,
  animcheck, bots...). Its Python tools run here (`py -3 -I tools/test_all.py`). Our notes for it:
  `toolkit-coop-anything/games/grand-theft-auto-san-andreas/NOTES.md` (local, nothing published).
- Bad network (chaos-test.ps1, chaos relay profiles good_wifi..hell + outages): a 10 s outage dropped the partner
  for good (client ENet timeout ~5 s, server 30-60 s). The client now waits 30-60 s too. All profiles pass.
- Animation sync (anim-sync.ps1 + animcheck): walking showed as running for controller players (stick sent as
  -1/0/1); full stick range now (shared header: everyone needs this build). Rebuilding another player's CJ with
  RebuildPlayer(ped, false) used our fat/muscle and collapsed its skeleton; wrapped at 0x5A82C0 so other players
  keep their own body values. Open: on the host, joined players' bones still read collapsed (see NOTES.md).
- User tracks: random bytes named .mp3 froze the game 8+ s when the user-track radio stopped or retuned
  (usertrack-hang.ps1); the sync now shares/accepts only files whose header is real audio.
- Mid-session soak (30 min, 602 actions): no crash; the one hang was the fake-song radio above.
- Tests: tracks-test now uses real (silent) WAV/MP3 songs; respawn waits use Wait-Playable; mission-sweep.ps1
  defaults to the test copy. New autotest commands: animprobe, face, clothes, press with fwd/walkfwd/... and a+b.
- Never use the game's screenshot writer in tests: JPegCompressScreenToFile captured the real desktop (removed).

## 2026-10-25 15:30: Crashes found by random two-player play (soak test) fixed (6f988ce..ab6e8d3)
- New tests: soak-test.ps1 (host + partner through the lag simulator, random actions for N minutes, actions.txt),
  replay.ps1 (replays an actions.txt with the same timing, -Skip to narrow a crash down), cutscene-death.ps1.
- A partner dying during the host's mission cutscene failed the mission without clearing the cutscene; it kept
  running on both games and the next mission's cutscene crashed the camera (CCam::Process_FlyBy).
  CCutsceneCleanup: a cutscene the mission left behind is finished and cleared 1 s after the mission ended, and
  the local player can't be hurt while a cutscene plays (no control, like single player).
- The host starting a mission while a partner still lay dead: the death check unwound the new mission script
  before its first gosub (stack index wrapped to 65535), the host crashed on a garbage opcode. Without the crash
  the mission would have failed at once. Now other players count only once seen alive in this mission
  (CMissionDeathCheck), the unwind needs a return address, and a dead partner shown idle with 0 health counts
  (before, such a death could leave the mission running).
- Crash after ~10 min of busy play (both games, CColModel::AllocateData on null in the hit-collision code): the
  collision-model pool was full (10150/10150). With these mods the game starts at ~9980 and city trips, deaths
  and missions add ~10-70 each (streaming, it levels off: pool-probe.ps1). GameHooks raises the pool to 20000 at
  startup (CPools::Initialise's push 10150 at 0x551106, only if unchanged). Status shows pools.colModel/Size.
- Test-only: the autotest heal/startmission refuse a dead player (healing a dying player caused the earlier
  soak crashes, not a game bug). `kill` is now a real deadly hit (damage event); `kill hard` only zeroes the
  health, which in a scripted scene left the player walking around with 0 health and never respawning (a test
  artifact: the game takes no damage then). The first death of a game plays the hospital tutorial (~25 s without
  control); tests wait with Wait-Playable (lab-common.ps1). New tests: respawn-health.ps1, barber-pair.ps1.

## 2026-10-25 05:00: Shared saves, user tracks, passenger radio, gang territories, silent crashes (df4bc6d..a8a90a4)
- Crashes: no crash windows any more. CCrashLog writes the log to CoopAndreas_crashes, sends the report (4 s max),
  exits with 0xC0DE and does not hand the crash on; KeepHandler takes the handler back every 2 s (modloader
  plugins replaced it, so the real game crashed without a log). Game folder: CrashInfo.ini Enabled = 0
  (backup in backup-original\CrashInfo.ini.before-2026-10-25; set 1 to undo). crash-test.ps1 on the real game.
- Test games no longer touch the real Documents: GetUserFilesFolder's 3 call sites are wrapped in --autotest
  (%TEMP%\coopt-<autodir>; a long path overflowed game buffers, switching later crashed). An earlier save test
  had written slots 6-8 into the real folder; those files were moved to testing\reports\stray-test-saves-2026-10-25.
- Save sync (CSaveSync): whoever saves, the host saves that slot and sends the file to everyone (8 KB pieces,
  CRC, old file kept as .bak); not while the host is on a mission/in a cutscene/wasted. Each player's look
  (clothes, fat, muscle) is kept in GTASAsfN.b.coop and restored when that save is loaded. save-sync.ps1 8/8 incl.
  a partner starting the game by loading the shared slot.
- User tracks (CUserTrackSync): song lists every 20 s, missing songs downloaded from their owner one at a time
  (mp3/ogg/wav/wma, max 40 MB, never overwriting), lost requests retried. tracks-test.ps1 (3 runs).
- Passengers follow the driver's radio station (reliable for station changes; at the start of a ride the radio
  may stay off up to ~30 s - the game's own passenger radio logic, not understood further).
- Gang territories (CGangZoneSync): zone strengths/colours from the host (layout verified at runtime).
- Loading a save mid-session crashed once (CEntity::RegisterReference in the restart); 7 targeted repros since
  (host/partner, after a mission, after look changes) did not crash again.
- Tests: quick-fixes 13/13, markers-test 8/8, save-sync 8/8, tracks-test, train-test (incl. gang zones), crash-test.

## 2026-10-25 02:40: Host-run missions shared with partners, smooth cars, trailers, trains (commits 5287cbe..ccd37b2)
- Measured first (testing/gap-probe.ps1, host + partner per mission): money was already shared (200/200, 8000/8000);
  partners missed the 3D "go here" markers, race checkpoints, blips on pickups and objects.
- New packets (server rebuilt, everyone needs this build): MISSION_MARKERS (locate areas + script checkpoints of
  host-run missions), MISSION_PICKUPS / MISSION_PICKUP_COLLECTED (mission pickups; a partner collecting one counts for
  the host's script), MISSION_FIRES / MISSION_FIRE_OUT (spot fires, put out by anyone), MISSION_TRAINS (every train
  the host creates; partners build it on the host's node/track, follow its rail distance and speed).
- Host-run missions' objects are now network objects too (WorldHooks), e.g. Green Goo's crates and their blips.
- Cars driven by other players glide instead of jumping (60+-20 ms link: back-steps 2-7% -> 0%); trailers hook on.
- Fixed crashes found by the new tests: radar pins of a player without a ped (upstream, partner starting a side
  job); a partner building a train before its models were loaded (caught before release).
- CAT1 and CATCUT (the two freezes) start and pass with 2 players now. Side jobs start for host and partners.
- Respawned partners: ported missions fail for everyone when a partner dies; 1D02 globals follow a respawn anyway.
- Test copies: CrashInfo.SA.asi renamed .off-for-tests (undo: rename back). Test-only: hidden games skip the
  underwater screen effect (crashed minimized windows). Deployed to the real game afterwards (alt-tab 3/3, barber).
- Tests: quick-fixes 13/13, markers-test 8/8, car-jitter 4/4, train-test, side-jobs, gap-probe over 30 missions.

## 2026-10-24 05:30: Deployed e733c88 to the real game, zips rebuilt
- build.ps1 -Deploy + build-scm.ps1 into GTA San Andreas (game closed). Checked there: alttab-repro 3/3, barber-solo pass,
  no new crash logs. friend-package: GTA-SA-coop-full-2026-10-24.zip (3.86 GB), CoopAndreas-coop4-2026-10-24.zip
  (3.3 MB); older coop4 packages removed.

## 2026-10-23 22:00: Alt-tab freeze (real cause), partner car marker, one barber chair, lighter overlay
- Tested only in the test copies "GTA San Andreas (test)" / "(test) (partner)" (testing/make-test-copies.ps1: data
  hard-linked, deployed files real copies, modloader off), on ports 16795-16799, while friends played on the real game.
- Alt-tab freeze: the bundled Widescreen Fix (AllowAltTabbingWithoutPausing = 0) opens the pause menu when the
  window gets focus back. In coop that left the game paused (userPause), often with nothing drawn, so "can't move";
  anything stealing focus (Discord, notifications) did the same. CCustomMenuManager::CloseFocusPauseMenu (per frame)
  closes a pause menu that opens within 1.5 s of a focus change; Esc later still opens it. The earlier keyboard
  clear alone did not fix it. Repro: testing/alttab-repro.ps1 (posts the real focus messages during a cutscene).
- Extra partner vehicle: its blue blip is removed while anyone sits in it and comes back when it's empty again.
- Barber/tattoo chair: new condition 1D21 Coop.IsAnyNetworkPlayerInArea3D; a player only gets the chair blob while no
  other player stands in the chair spot (1.5 m). One barber, one customer at a time.
- Sanny Builder compiles with its own copy of sa_coop.json/.db (C:\Tools\SannyBuilder4\data\...); a command missing
  there compiled to NOTHING without an error (the raw `not 1D21:` line vanished and broke the chair). build-scm.ps1
  now syncs both files from the repo before compiling. Use the class syntax (Coop.X) with a db entry.
- Overlay cost (testing/perf-probe.ps1, status `coopUs`): coop's own drawing went from ~230 to ~80 us per frame:
  chat text is batched in one D3DX sprite with cached widths, text is drawn with one drop shadow instead of a
  4-sided outline (each DrawText ~25-35 us), and the alpha version label shows only while typing in chat.
- Test scripts quick-fixes.ps1 / perf-probe.ps1 now stop only their own game copies (they used to kill every
  gta_sa.exe, including a game someone is playing) and default to the test copy.
- Autotest: status `pad` (input/pause state), `minigame`, `coopUs`; events menu_opened/menu_closed,
  focus_pause_closed, chair_check; `vehicle <model> mission`. quick-fixes.ps1 has 12 checks.

## 2026-10-23 16:20: NPC jitter fixed
- Synced on-foot NPCs snapped to every update (20/s) and their local AI moved them in between. CNetworkPedManager now
  glides them towards the predicted owner position (last synced position + velocity, max 200 ms ahead), 25% of the
  gap per 50 fps frame, height left to local physics (unless >1 m off), snap only beyond 6 m.
- Measured with testing/jitter-tune.ps1 (partner watching the host's NPCs at Grove Street): moving frames where an NPC
  steps backwards: old 5.7-7.3% -> 0% (strength 0.15-0.25; 0.4 overcorrects to 5%); host's own NPCs 0%.
- Autotest: `smoothing <0|1> [strength]`, status npcJitterCm (= snap-back %), npcJitterSamples, ownNpcJitterCm.
  quick-fixes.ps1 has a jitter section: 10/10; lab 34/34.

## 2026-10-23 15:50: Fixes from the first session with friends (testing/quick-fixes.ps1: 9/9)
- Wanted level no longer shared: unported missions' alter/clear_wanted_level were broadcast to everyone (my earlier
  change); money rewards stay shared.
- Radio: remote players are player peds, so a friend entering any car switched the single global radio to it
  (CAEVehicleAudioEntity service 0x50237C/0x5023A3, and 0x45F159 via FindPlayerVehicle(-1) while PlayerInFocus is a
  remote player). Hooks let only the local player's vehicle switch the radio. Status `radioCar` none/mine/other.
- Alt-tab: the game keeps running unfocused, so keys held while alt-tabbing never got their key-up (stuck "Alt =
  walk" etc.; no movement after a cutscene). Keyboard states are cleared on focus changes (CCore WindowProc).
  Not reproducible in the automated test (no real keyboard) - verify in play.
- Save point sent partners into the sky: the save menu sets the on-mission flag, which triggered the far-partner
  teleport to the host standing inside CJ's house (interior coords, other area). Now only for a real mission
  script, and never while the host is in an interior.
- Barber (and food, shop staff, tattoo) spawned one shopkeeper per player: every player's shop script created its
  own when players walked in together. Partners now wait up to 2 s for an existing one (BARB/JFUD/PSHOP/TATTO).
- Interior/exterior mix-up (Cleaning the Hood): the host's set_area_visible is broadcast, but partners are moved
  in/out separately; a partner who missed it stood outside with the interior area shown (white sky). New
  CAreaConsistency: outside cutscenes/scenes, the visible area follows where the local player really is.
- Mission markers with more players: partners count within 3.5 m of the marker (Ryder's was ±1.2 m for everyone),
  and partners far away (>50 m), dead or in another area no longer block the start - it starts with whoever is there.
- Autotest: commands `wanted`, `countpeds`, `enex`; status `radioCar`, `area`.
- Not fixed yet: NPC jitter (no interpolation of synced peds - upstream TODO "smooth interpolation", backlog).

## 2026-10-23 13:40: Connect menu port crash fixed
- Deleting the last digit of the Port field crashed the game (KERNELBASE.dll): CCustomMenuManager called std::stoi on
  the empty field. Now strtoul; typed digits are null-terminated; a digit that would make the port > 65535 is refused
  (it wrapped). Upstream bug. Deployed, friend zips rebuilt. Not exercised in-game by a test (menu typing).

## 2026-10-23 13:20: Serial key removed
- Client: CLaunchManager (the upstream beta key check: hash of the PC id vs `-serial`, else exit) removed; it also
  strtok'd the shared command line. Launcher: no dialog, it runs `gta_sa.exe --coop` (pcid/clipboard/registry helpers
  removed). Test scripts no longer read HKCU\Software\CoopAndreas. HOW-TO-PLAY / friend README updated.
- Verified: the launcher starts `"gta_sa.exe" --coop`; lab 34/34 without any key. Deployed together with the 89
  pass labels (main.scm).

## 2026-10-23 12:40: Pass sweep rerun (stopped), catalog fix, full game zip for friends
- Pass sweep rerun on the current build (visible windows on request), stopped by the user after ~53 missions: missions
  11-20 all pass through their own routine with the banner on 3 bot partners; MISSIONS.md regenerated: 102/102 clean
  start/cutscene/fail, 63/102 pass. mission-catalog.ps1 now classifies whole report folders as pass or fail sweeps (a
  stopped pass sweep had overwritten the fail-sweep column).
- testing/make-full-zip.ps1: zips the coop-ready game folder (user's request; friends own the game) without crash
  logs, autotest files and logs, plus CoopAndreas Server\ (server.exe + config) and HOW-TO-PLAY.md ->
  friend-package\GTA-SA-coop-full-2026-10-23.zip (3.86 GB). No serial key in it (that lives in the registry).

## 2026-10-23 04:30: Missions passed for real: pass sweep, real 2-game playthrough of Big Smoke / Ryder
- `passmission` autotest command: Rockstar's debug "S = pass" (`0735 is_keyboard_key_pressed 83`, 86 scripts) answers
  true for the mission script -> its own pass routine. 19 story missions without it got `1D20: @<pass block>`
  (new custom command Coop.SetAutotestPassLabel, testing/add-pass-labels.ps1); passmission jumps there.
  `mission-sweep.ps1 -EndBy pass`, `lab-duo.ps1 -Pass` (real partner: pass banner on both, money equal).
  First pass sweep (before the labels were deployed): 47 passed through their pass routine with the banner on all 3
  partners; sweep half A stopped answering commands after CATCUT (45) — the sweep now restarts an unresponsive game.
- Sanny gotcha: `Coop.X(...)` class syntax comes from the precompiled sa_coop.db; a command added only to sa_coop.json
  is silently dropped. New commands are written raw (`1D20: @label`).
- **Big Smoke played to MISSION PASSED with two real games, no shortcut** (testing/playthrough.ps1, 4 of 4 runs):
  marker start with both players, INTRO1A/INTRO1B skipped 2/2, the drive-by scene, both on BMXs following Sweet to the
  all-players checkpoint at 1644,-1051, the "split up" scene, following Ryder to Grove Street, everyone in the final
  marker -> M_PASSR on host and partner. Scripted partner teleports measured when each scene ends: 3.7 / 3.9 / 6-9.6 m
  from the host (script spots: 954.8,-1100.6 after the drive-by, 1636,-1047.5 after split-up).
- After Big Smoke the game's hint "Go inside CJ's house to continue": host and partner walk through CJ's door (CARLS,
  interior 3) and back out -> INTROST restarts the INT trigger -> Ryder starts from its marker with both players.
- **Ryder played to MISSION PASSED with two real games, no shortcut** (play-2026-10-23_09-53-38): INTRO2A, Ryder's car
  to the barber, BARBERS door, haircut bought in the shop menu ($50), out, the outside-barber scene, Well Stacked Pizza
  door + menu ($2), robbery scene, drive Ryder home -> M_PASSR on host and partner. Partner placed 1.0-3.1 m from the
  host by every scene (10 m at the end scene).
- Fix (real coop bug, scm/scripts/INTRO2.txt): the finish needed every partner within 20 m of 2491.8,-1667.9 while
  Ryder's house marker is ~30 m away - a partner parked next to the host's car kept the mission from ending. Now 30 m
  around 2478,-1685.
- Fix (crash, Hooks/VehicleHooks.cpp): vehicle deleting destructors call operator delete(nullptr) when the destructor
  chain returns with ESI = 0; the freed vehicle's slot stayed "used" and CWorld::RemoveReferencesToDeletedObject
  crashed on it (2 host crashes in playthroughs: end of Big Smoke, leaving the barber). VehicleDtorShim keeps ESI
  around the destructor call for all 10 vehicle classes; no crash since.
- Playthrough lessons now in the driver and HOW-TO-PLAY: partners take their own blipped vehicle (Ryder can't get
  into his Picador if a partner sits in the only seat); shop menus = locked controls inside: buy, then leave, then walk
  out and step off the door (standing on it walks you back in); everyone has to come out of the shop for the scene.
- Autotest: `press` is applied right after CPad::UpdatePads (0x53BEE6; before, CGame::Process re-read the pads and
  overwrote it); status blips are only the ones this player sees (SetBlipVisibleTo); teleport refuses a target on
  the other side of a door (fatal falls); visible-mode screenshots use PrintWindow (they had copied the screen area,
  i.e. whatever covered the game).
- Client autotest additions for this: status `blips[]`, `markers[]`, `doors[]`, players[].interior; commands
  `enterpassenger`, `press <button> [ms]` (pad), `interior <area>`, `walkto x y z`; `entermissioncar` prefers the
  blipped vehicle (within 200 m). `testing/gxt.ps1` prints GXT texts.

## 2026-10-23 00:50: Bad-link vehicle crash fixed; test games fully hidden
- Root cause of the 150 ms/5% loss crash: the game calls `CVehicle::operator delete(nullptr)` (gta_sa 0x6B1345,
  0x6B8965); the original 0x6E2D90 has no null check and sets the vehicle pool's next-free index to a huge negative
  number, so the next vehicle is constructed outside the pool. New hook on 0x6E2D90 refuses null / non-slot / free
  slot pointers (`vehicle_delete_refused` event; seen ~1x per harsh run, harmless now) + next-free index repair in
  CNetworkVehicle::CreateVehicle. Also: CreateVehicle skips when the pool is full; traffic generation keeps 16 slots free.
  9 harsh duo runs since (150±40 ms, 5% loss): 15/15 each, no crash log.
- `-autohide` reworked: patched gta_sa imports (no-activate window at the bottom of the z-order), CBT hook vetoes
  activation, no dev console in hidden runs (it took focus), minimized after ~300 in-game frames (event
  `window_hidden`). New `testing/focus-watch.ps1`: 0 foreground samples during lab and duo runs.
- Lab/duo waits lengthened (minimized games run ~27 fps). Lab 34/34 hidden.

## 2026-10-22 23:40: 102/102 story missions; network simulator; upstream checklist
- Lowrider (High Stakes): starts, cutscene, runs and ends when CJ is in a lowrider (real-play condition); sweep has
  `$MissionPrep` for it. Monster / Home Coming clean in 2 more runs. MISSIONS.md: 102/102 story missions clean.
- New `CoopAndreasNetSim.exe` (xmake target netsim) + `lab-duo.ps1 -Net`: 75 ms/2% loss 15/15; 150 ms/5% loss crashes
  the joining partner in the vehicle ctor (2/3 runs) — logged in the AGENTS.md backlog with repro.
- New `UPSTREAM-SYNC-CHECKLIST.md` (testing/upstream-checklist.ps1): all 282 upstream TODO items vs this fork.
- Unported-mission notice made neutral ("[CoopAndreas] Host-driven mission…"), main.scm rebuilt + deployed.

## 2026-10-22 23:20: Newest build back; full parallel sweep: 101/102 story missions clean
- Redeployed the newest build (CJ hiding now only in cutscenes or widescreen scenes *without player control*;
  autotest ignores real skip-button input — the user's clicks made the host vote on its own). Lab 34/34.
- Parallel sweep 11–112 (~40 min): 92 clean; reran the 8 others on a build whose startmission refuses while code runs
  in the mission block (Lowrider left helper scripts there → launching the next mission crashed gta_sa+0x6952A) and a
  sweep that restarts the game after any stuck mission: 7 more clean → **101/102**. Open: Lowrider (High Stakes)
  closes the game when launched directly on a fresh save.
- MISSIONS.md regenerated; MISSION-COOP-BUILD.md section 4a.

## 2026-10-22: User asked for a playable version without the latest extras → stable build deployed
- Paused the parallel sweep (it uses the game folder; two games side by side crash modloader).
- Built commit **e34b87e** (fallback sync, shared money/wanted, far-partner teleport, text dedupe; NO partner cars,
  NO cutscene CJ hiding) in worktree `coop-dev/CoopAndreas-stable`, deployed it to the game folder + `server/`.
  Lab on it: 31 passed; the 2 CJ-hiding checks fail as expected (feature not in this build) and one vote check failed
  because the skip button was pressed in the game window during the run (vote code identical in both builds).
- Friend zip of exactly this build: `friend-package/CoopAndreas-stable-2026-10-22.zip` (README without the partner-car line).
- To go back to the newest build: `testing\build.ps1 -Deploy` (+ `build-scm.ps1`), then resume the sweep.

## 2026-10-22: Deployed + verified newest build; friend package
- Deployed (CJ hiding, nowanted, startmission sets onmission). Headless 8/8, lab mission scenario 23/23 (CJs hidden
  during INTRO1A and shown after; INTRO1B vote resets 0/2 → 2/2), duo 15/15 (partner sees objective blip).
- Lab test fixes: INTRO1B can start within seconds of INTRO1A, so those checks search the whole event log.
- `friend-package/CoopAndreas-coop4-2026-10-22.zip` (2.4 MB): install.bat/uninstall.bat verified on a dummy folder
  (eax.dll kept as eax_orig.dll and restored, CLEO+ moved aside). HOW-TO-PLAY no longer says to zip the game folder.
- Parallel re-sweep 11–112 started on this build.

## 2026-10-22: First full mission sweep done; cutscene CJ hiding; documentation
- Full 4-player sweep of story missions 11–112: **86/102 clean**; 8 don't end on host death; 4 crashed (all
  silentpatchsa.asi+0xAAC0 shortly after a game restart); 4 don't start from a fresh save. Details:
  MISSION-COOP-BUILD.md and MISSIONS.md.
- New `CCutscenePlayerHider` (client): other players' CJs invisible during cutscenes/widescreen scenes.
- Autotest `nowanted`; sweep ends missions with fail_current_mission (no more killing CJ), 15 s run,
  `mission-sweep-parallel.ps1` (2 games at once). Built, **not yet deployed/lab-tested** (user stopped the deploy).
- Docs: MISSION-COOP-BUILD.md (what was built for missions, tools, results, open items).

## 2026-10-22: Partner vehicles, failmission, blip check
- New `CMissionPartnerVehicles` (client, host): extra copies of the host's mission vehicle when NPCs leave no seats
  for partners. Sweep with entermissioncar: Ryder 2 cars, Drive-Thru 1, Drive-By 1, Tagging Up Turf 0 (enough seats).
- Autotest: `entermissioncar`, `failmission` (045C), status `objectiveBlips`; duo lab checks partner blips.
- Sweep: fails leftover mission scripts (farlie4 from Ran Fa Li blocked missions 55–73 in the previous run),
  fails missions that ignore host death with failmission, records partnerCars/teleports.
- Undo: revert commit b201f37 (+ following) in CoopAndreas and redeploy.

## 2026-10-22: Partner verified with a 2nd real game; teleport + dedupe; Sanny Builder toolchain
- `testing/lab-duo.ps1`: **14/14** — a real partner client sees the host, gets the unported mission's cutscene,
  its skip vote reaches the host, both cutscenes end at 2/2, partner sees MISSION FAILED, mission flag ends.
- `testing/make-partner-copy.ps1` → `GTA San Andreas (partner)` (hard links; modloader off, essentials in scripts\)
  because modloader.asi crashes in a 2nd concurrent instance (the crash the user pasted at 20:41, modloader+0xA34E).
- Unported missions: partners >50 m away are teleported next to the host on mission start / when the script moves
  the host; repeated identical print/print_now/print_help keys sent once per 2 s (mission 17 sent 235 texts before).
- The 6 scripts with the "unsupported mission" chat warning now say the host drives it and what partners get
  (RYDER2, RYDER3, SMOKE3, SWEET2, SWEET4, SWEET6); main.scm rebuilt and deployed.
- Sanny Builder 4.2 installed to C:\Tools\SannyBuilder4 + repo sdk overlay; mode.xml `@game:` set to the game path;
  `testing/build-scm.ps1` compiles (unmodified sources = byte-identical to shipped main.scm/script.img) and deploys.
- Sweep: missions 11–26 all clean with 4 players (first run, previous build). OG Loc (27, ported) does not end when
  the host dies — recorded as a note; the sweep now restarts the server with each session (killed bots kept slots).
- Undo: `git checkout` older commit in CoopAndreas, `testing/build.ps1 -Deploy`, `testing/build-scm.ps1`.

## 2026-10-22: All missions: fallback sync, 4-player sweep, catalog, sync backlog
- **Unported mission fallback** (`client/src/COpCodeSync.cpp`): for the ~95 missions upstream hasn't ported
  (no `Coop.EnableSyncingThisScript`), the host now syncs their texts (print/print_now/print_big/
  print_with_number_big/print_help/clear_prints), `load_mission_text`, `register_mission_passed`, fades, widescreen and
  cutscenes (load/start/clear). Before this, partners saw no objectives or banners, never saw the cutscene, so the
  4/4 skip vote could never finish. Verified on Nines And AK's: partners got the cutscene, voted, got SWE2_A + M_FAIL.
- **Shared money + wanted level in unported missions**: add_score / alter_wanted_level(_no_drop) / clear_wanted_level on
  the host's `$player1` are sent with a plain 0 player param, so every client applies them to its own player.
  Ported scripts are unchanged (wanted stays unsynced there, add_score as upstream). Built; verify with a 2nd real game.
- **Crash fix (autotest only)**: `startmission` launched while the INITIAL mission script was still running → mission
  code overwritten → null opcode handler in `FinishedOpcodeProcessing_Hook` (the 0x00000000 crash pasted by the user,
  resolved with the new map file). `startmission` now refuses while any mission script runs.
- SilentPatch audio-stream crash (silentpatchsa.asi+0xAAC0) when a cutscene starts seconds after a new game: the sweep
  waits 15 s after boot. Not seen when started later.
- New: `testing/mission-sweep.ps1`, `testing/mission-catalog.ps1` → `MISSIONS.md`, `testing/resolve-crash.ps1`,
  client link map `CoopAndreas/build/CoopAndreasSA.map` (xmake `add_shflags("/MAP:...")`).
- Autotest: `startmission <id>`, events `mission_script` (with `synced`), status `money`/`wanted`.
- Bot: decodes texts inside OPCODE_SYNC (print opcodes), counts texts/banners/cutscenes/votes, follows
  TELEPORT_PLAYER_SCRIPTED in `--stand` mode.
- AGENTS.md: "Missions in coop" + full **Sync backlog** (upstream TODO + our findings).

## 2026-10-22: Lab mission scenario (Big Smoke with a 2nd player)
- Client autotest: mission/cutscene/skip-vote events, status fields onMission/mission/cutscene/skipVotes,
  `kill` and `skipcutscene` commands, `-autodir`. `CCutsceneSkipVote` got GetVotes/GetVoters/HasVoted/PressSkip
  (PressSkip only acts like one press of the skip button).
- Bot: `--stand`, `--vote-skip`, mission traffic log (on-mission flags, opcode sync incl. cutscene opcodes,
  vote states, GXT texts), unbuffered stdout.
- `lab.ps1 -Scenario mission`: 20 checks, about 50 s, passed twice in a row. Full lab: 32 checks + 1 known gap, 78 s.
- Verified working: the all-players marker trigger, the INTRO1A/INTRO1B cutscenes, the skip vote (waits for every player,
  2/2 skips), the scripted drive, fail by death plus hospital respawn, and Player2 getting on-mission 1→0, cutscene
  load/start/clear opcodes and the dialogue texts.
- **Gap found (upstream):** player 2 never gets the "MISSION FAILED!"/"MISSION PASSED!" banner. Mission scripts print
  M_FAIL/M_PASS* with plain `Text.PrintBig`/`PrintWithNumberBig` (hundreds of call sites), and only
  `Coop.ShowText...ForNetworkPlayer` texts are sent. Tracked as a `Known` check in the lab (GAP → FIXED when solved).
- Not covered yet: passing a mission (Big Smoke needs the BMX chase), and a 2nd *real* game as player 2.

## 2026-10-22: Test lab + CLEO hook bug fixed
- **Bug (affected real play):** CLEO 4.4 redirected the CGame::Process call (0x53E981) away from plugin-sdk without
  chaining, so CoopAndreas' per-frame code never ran. The game connected but never finished the handshake, and nothing synced.
  Found with `testing/hookcheck.ps1` (0x53E981 → CLEO.asi+0xE1A0). Fix: `CPatch::Remember/ReclaimGameProcessHook()`
  restores our hook after all ASIs load (WinMain after window init + initGameEvent). CLEO scripts don't run in coop.
- New autotest mode in the client (`client/src/CAutoTest.*`, `--autotest -autoip -autoport -autoname`): skips the menu,
  writes `CoopAndreas/autotest/events.jsonl` + `status.json`, runs commands from `commands.txt`. Hooks are in
  CCore (init), CCustomMenuManager (menu frame), Main.cpp (game frame) and the chat packet handler. It does nothing without the flag.
- Bot now syncs the server clock like the real client (SERVER_TIME_REQUEST every 1 s), so its movement timestamps are realistic.
- Server stdout is unbuffered (`setvbuf`), so lab logs are readable live.
- New scripts: `testing/lab.ps1`, `lab-common.ps1`, `lab-cmd.ps1`, `hookcheck.ps1`. Removed the first draft `ingame-test.ps1`.
- Results: lab **16/16 pass on 3 consecutive runs** (about 37 s each, no screenshots); headless `run-tests.ps1` 8/8.

## 2026-10-22 — Startup crash fixed, CLEO+ disabled
- Crash (`CoopAndreas_crashes\2026-10-22_19-09-5*.log`): access violation at 0x748731 in WinMain on every coop launch.
  Cause: `CPatch.cpp` picks its isAlreadyRunning patch with `GetModuleHandleA("SilentPatchSA.asi")`. Our SilentPatch
  is loaded by modloader *after* CoopAndreas, so the check failed and it NOP'd 0x74872D. SilentPatch then hooked that same
  call, so the game jumped into the middle of an instruction.
  Fix: `IsSilentPatchInstalled()` also looks for `SilentPatchSA.asi` in the game dir, `scripts\` and anywhere under `modloader\`.
- CoopAndreas refuses CLEO+ (other players don't see your shots). Moved `CLEO\CLEO+.cleo` to `coop-dev\disabled-mods\CLEO\`.
  Undo: move it back (only single player needs it, and no installed .cs script uses it).
- Verified: coop launch with the real serial key reaches the game (window "CoopAndreas", 77 fps) with no crash log.

## 2026-10-22 — Session 1: 4-player coop build, test system, deploy

### Fork changes (branch `coop4`, commit 8d7e578 on top of upstream df03bbf)
- `server/src/CNetwork.cpp`, `server/src/ConfigManager.h`, `shared/config.h`: the server now reads `maxplayers`
  from `server-config.ini` (it was a TODO upstream). It defaults to 4 and is capped at `MAX_SERVER_PLAYERS` (8).
  ENet refuses the 5th connection.
- `client/src/CCore.cpp`, `client/src/CPatch.cpp`: debug multi-instance now takes `--coopd0`..`--coopd3`
  (upstream allowed 0-1). The windows tile in a 2x2 grid.
- `client/src/CConfigLoader.cpp`: in debug runs each instance uses `coopd<N>_coopandreas.ini`, so local
  test windows keep different nicknames.
- `launcher/src/main.cpp`: also saves the PC id to `HKCU\Software\CoopAndreas\PcId` so test-local.ps1 can start instances.
- New `testbot/` target, `CoopAndreasBot.exe`: a headless player that speaks the real protocol
  (join, on-foot sync at 20 Hz, chat) and reports what it received as JSON.
- Undo: `git checkout main` in `CoopAndreas/`.

### Test system (`testing/`)
- `build.ps1` builds everything (`-Deploy` installs into the game, `-Uninstall` restores the original eax.dll).
- `run-tests.ps1` runs automated tests with no game needed. Result: **8/8 pass**
  (4 players see each other's movement and chat, the 5th is refused, the server refills after everyone leaves,
  a duplicate nickname is rejected, the server stays up).
- `test-local.ps1` starts a server, up to 4 real game windows and headless bots to fill the remaining slots.

### Game folder changes (deployed by build.ps1 -Deploy)
- `eax.dll` → `eax_orig.dll` (original, MD5 matches backup); new `eax.dll` = CoopAndreas proxy.
- Added `CoopAndreasSA.dll`, `LaunchCoopAndreas.exe`, `LaunchCoopAndreas.exe.manifest`,
  `CoopAndreas\main.scm`, `CoopAndreas\script.img` (prebuilt in the repo, same commit as `scm/main.txt`).
- Smoke test: `gta_sa.exe --coop` with a bad serial shows "Failed to verify CoopAndreas serial key", so the proxy and
  client load. Plain `gta_sa.exe` still starts normal single player.
- Undo: `testing\build.ps1 -Uninstall`.

### Tools
- Installed Ghidra 12.2 to `C:\Tools\ghidra_12.2_PUBLIC`, set user env `GHIDRA_INSTALL_DIR` and `JAVA_HOME` (Temurin 21) for REA native analysis.
- Code graph: `graphify-out/` (2594 nodes, 4632 edges; hubs: Packet, ePacketType, CNetworkPlayer, CVehicle).

### Not verified yet
- A real in-game session with 2+ people: it needs the free beta serial key from the CoopAndreas Discord (`/gen <id>`).
- Compatibility with the Essentials pack (Framerate Vigilante vs CoopAndreas' own framerate patch, CLEO scripts).

## 2026-10-22 — Session 1: setup
- Installed toolchain (winget): Git 2.55, Node 22, Python 3.12, uv, xmake 3.1, ffmpeg, VS 2022 Build Tools (C++ x86/x64, Win11 SDK), Temurin JDK 21.
- Installed agent tools: `rea-agents` 6.7 (npm global, CLI `rea`), `graphifyy` (uv tool, CLI `graphify`), `universal-modder` 0.2 (uv tool, CLI `um`).
  - NOT done (blocked by agent auto-mode, the user must run them): `rea setup --client claude-code`, `graphify install --platform claude`, `npx skills add vercel-labs/agent-skills`.
- Cloned Tornamic/CoopAndreas @ df03bbf (2026-10-20, "implement mission object syncing"), version 0.3.0-alpha, upstream MAX_SERVER_PLAYERS = 8.
- Backed up `eax.dll`, `gta_sa.exe` (MD5 2B5066BD4097AC2944CE6A9CF8FE5677, 1.0 US Hoodlum + 4GB), `stream.ini` and `Documents\GTA San Andreas User Files` to `backup-original/`.
