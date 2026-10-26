# AGENTS.md — GTA San Andreas 4-player coop

Read this first, then MODLOG.md (newest entries at the top), before touching anything.

## Goal
Make GTA San Andreas (PC 1.0 US) playable in online coop with up to 4 friends: free roam, cars,
weapons, chat, and as much of the story as possible.

## Layout
| Path | What |
|------|------|
| `../GTA San Andreas/` | The game install (1.0 US Hoodlum exe + MixMods Essentials: CLEO 4.4, ModLoader, SilentPatch, Widescreen Fix, Windowed Mode, Framerate Vigilante). |
| `CoopAndreas/` | Fork base: https://github.com/Tornamic/CoopAndreas (GPL-3.0). Client DLL, server, eax.dll proxy, launcher, main.scm. |
| `testing/` | Our test system: build/deploy script, multi-instance launcher, headless bot clients. |
| `backup-original/` | Untouched copies of `eax.dll`, `gta_sa.exe`, `stream.ini` and the save folder. Restore from here. |
| `graphify-out/` | Code knowledge graph of CoopAndreas (`graph.json`, `GRAPH_REPORT.md`). Query it with `graphify explain "X"` / `graphify path "A" "B"` before grepping blind. |

## How coop loads
1. `gta_sa.exe` loads `eax.dll`. Our `eax.dll` is the CoopAndreas proxy; the original is renamed `eax_orig.dll` and every export is forwarded to it.
2. If the command line contains `--coop`, the proxy loads `CoopAndreasSA.dll` (the client).
3. Without `--coop` the game runs as normal single player — the install stays usable.
4. No serial key (removed 2026-10-23 at the user's request; upstream had a local beta check `-id <pcid> -serial <key>`
   in client/src/CLaunchManager.cpp + a launcher dialog). The launcher just runs `gta_sa.exe --coop`; old `-id`/`-serial`
   arguments are ignored. When merging upstream, keep CLaunchManager out.
5. Server: `server.exe`, UDP port 6767 (ENet). Players need that port forwarded on the host's router, or a VPN LAN (Tailscale/ZeroTier/Radmin).

## Build
Toolchain: VS 2022 Build Tools (MSVC x86), xmake. Sanny Builder 4 is only needed if you edit `scm/main.txt`
(the repo ships a matching prebuilt `main.scm` + `script.img`).
- `testing/build.ps1`: builds server, testbot, proxy, launcher and client (release x86) and copies `server.exe` to `server/`.
- `testing/build.ps1 -Deploy`: installs into the game folder. `-Uninstall` restores the original `eax.dll`.
Never commit or ship game files (`gta_sa.exe`, `.img`, `.scm` from Rockstar).

## Test
Run both after any client, server or network change, and keep them green.
- `testing/run-tests.ps1`: headless, about 40 s, no game needed. Server on port 16767 plus `CoopAndreasBot.exe` bots. 8 checks.
- `testing/lab.ps1`: **test lab**, about 37 s, with the real game. Starts a server (port 16768), the game with `--autotest`
  (auto new game, auto connect as `Tester`) and 3 bots, then checks everything through the game's own logs. 16 checks:
  per-frame hook alive, connect + handshake, host, bot peds spawn/walk/chat, car spawn/enter/exit as a network vehicle,
  bots see the game move + chat, cleanup, no crash logs. Screenshots only on failure (`-Shots` for always).
  Output: `testing/reports/<time>/` has report.json, `timeline.txt` (readable event log), events.jsonl, status.json,
  server/bot logs and copies of any crash logs.
  `-Scenario basic|mission|all` (default all, about 78 s). The **mission** scenario plays the first story mission
  (Big Smoke, INTRO1) with a second player (bot `Player2`, `--stand` in the marker, `--vote-skip`):
  marker trigger needs ALL players (`Coop.LocateAllPlayersOnFoot3D`, scm/scripts/INT.txt, marker 2495.2,-1687.0,12.5),
  INTRO1A cutscene and skip vote 1/2 → 2/2, the scripted drive, INTRO1B, fail by host death (M_FAIL), respawn, and
  what Player2 received (on-mission flags 1→0, cutscene opcodes 02E4/02E7, its votes, mission texts).
  `Known` checks print GAP/FIXED for documented upstream gaps and never fail the run.
- `testing/lab.ps1 -Keep` then `testing/lab-cmd.ps1 "<cmd>"`: interactive loop against the live game. Commands:
  `chat <text>`, `teleport x y z`, `vehicle <model>`, `leavevehicle`, `heal`, `kill`, `skipcutscene`,
  `entermissioncar` (warp into the nearest free mission vehicle, 80 m), `failmission` (opcode 045C, also ends
  leftover mission scripts like farlie4 that never set the on-mission flag), `startmission <id>` (host only; refused while any mission script runs, incl. INITIAL right after a new game,
  because missions share one code block and launching over a running one crashes),
  `passmission` (host: the next `0735 is_keyboard_key_pressed 83` executed by the mission script returns true —
  Rockstar's debug "S = pass" left in 86 scripts, which jumps to the mission's own pass routine: register passed,
  rewards, unlocks; event `debug_pass_taken`; retail returns false. Hook in Commands/CommandHooks.cpp; the check
  sits in one of the mission's loops, so it can take a while. The 19 story missions without that check carry
  `1D20: @<pass block>` (Coop.SetAutotestPassLabel, added by `testing/add-pass-labels.ps1`); for them passmission
  jumps there at once with the gosub stack cut to the main routine, `via=label`. Gotcha: Sanny resolves
  `Coop.Member(...)` syntax from `sa_coop.db` and compiles with its OWN copy in C:\Tools\SannyBuilder4\data
  (build-scm.ps1 now syncs json+db from the repo). A command missing there is silently dropped; a raw
  `not 1Dxx: ...` condition also compiled to nothing. Add new commands to json AND db and use `Coop.X(...)`),
  plus lab-only `status`, `events [n]`, `shot`. A player can't die during a cutscene.
  Each prints the events it caused. Don't pipe a `-Keep` run (the pipe waits for the game).
- `testing/mission-sweep.ps1 [-Missions "11-112"]`: **4-player mission sweep** (host + 3 bots `Mate1-3`, `--stand`
  `--vote-skip`, follow scripted teleports). Per mission: `startmission <id>`, skip every cutscene by a 4/4 vote, run
  25 s, fail by host death, respawn; records host events + what partners received; restarts the game on crash/stuck.
  About 1 min per mission. Output `testing/reports/sweep-<time>/missions.json|md`, crash logs, timelines of bad ones.
  `-EndBy pass` ends each mission through its own pass routine (`passmission`, 60 s, falls back to fail) — checks
  the pass banner/rewards reach the 3 partners. `mission-sweep-parallel.ps1 -EndBy pass` forwards it.
  `lab-duo.ps1 -Pass`: same with a real partner game (pass banner on both, shared money equal).
- `testing/mission-catalog.ps1`: regenerates `MISSIONS.md` (all 135 missions: port status, unsynced feature tags from a
  static scan, newest sweep result). Run it after every sweep.
- `testing/resolve-crash.ps1 0xRVA ...`: maps `CoopAndreasSA.dll+0xRVA` from a crash log to a function
  (uses `CoopAndreas/build/CoopAndreasSA.map`, written by every client build; only valid for that build).
- `testing/hookcheck.ps1`: shows which DLL owns key call sites in a running gta_sa.exe (finds hook conflicts).
- `testing/lab-duo.ps1 -Net [-Delay 75 -Jitter 15 -Loss 2]`: the partner connects through `CoopAndreasNetSim.exe`
  (xmake target `netsim`, testbot/netsim/main.cpp): UDP relay with one-way delay, jitter and loss — internet-like
  conditions on one PC. 75±15 ms / 2% loss: 15/15. 150±40 ms / 5% loss: no crash since the vehicle-delete guard (backlog).
- **Test games run hidden by default** (the user works on this PC while tests run): every lab/sweep passes
  `-autohide` (lab-common.ps1; set `COOP_LAB_VISIBLE=1` to see them, then screenshots work). With `-autohide` the
  client patches gta_sa.exe's imports (CreateWindowExA gets WS_EX_NOACTIVATE, ShowWindow → no-activate + bottom of
  the z-order, SetForegroundWindow/SetFocus/SetActiveWindow/BringWindowToTop → no-ops), a thread CBT hook vetoes
  any activation, no dev console is opened (showing it stole focus), and ~300 frames in-game the window is minimized
  (event `window_hidden`). Don't minimize during startup: a 0x0 client area stalls the frontend. Minimized games
  run ~27 fps. `testing/focus-watch.ps1 <script> [args]` runs a test and counts samples where a gta_sa window was
  foreground (must be 0).
- **`testing/playthrough.ps1 [-Missions "11,12"] [-Minutes 10]`: real playthrough, no pass shortcut.** Two real
  games (host + partner copy). Each mission starts through its real marker (both on foot in it), then a blip
  autopilot plays: skip cutscenes by vote; get into the blipped vehicle; escort blipped characters (stay within 8 m —
  the scripts freeze AI riders nobody is near, and finishes need them); go to drawn markers / coord blips only when the
  escort is within 50 m of it; destinations behind a door (z~1000 inside) go through the door (status `doors`); in a
  marker press cross/triangle (shop menus). The partner rides as the host's passenger (`enterpassenger`) or its own
  mission vehicle, follows blipped chars, joins the host in markers, follows into interiors. Nobody moves during a
  scripted scene (players_hidden..players_shown). Checks: start, MISSION PASSED on both, and the partner's distance to
  the host when each scripted scene ends (= the script's partner teleports). Between missions it does what the game's
  hint says (after Big Smoke: "Go inside CJ's house to continue" — INTROST then restarts the INT trigger for Ryder).
  Autopilot helpers in the client: status `blips[]` (type 1 car/2 char/3 object/4 coord, live entity position),
  `markers[]` (C3dMarkers; type 1 cylinders = locate "go here" markers; entry/exit doors are NOT in it), `doors[]`
  (entry/exits within 40 m: name, area, entrance centre), players[].interior; commands `enterpassenger`,
  `press <cross|triangle|square|circle|up|down|left|right|r1|l1> [ms]` (CPad NewState, applied in
  gameProcessEvent.before after the pads were read), `interior <area>`. Remote players' `isHost` is false on partners
  (find the host by name). `testing/gxt.ps1 KEY ...` prints GXT texts (objective keys from the scripts).
- `testing/upstream-checklist.ps1` → `UPSTREAM-SYNC-CHECKLIST.md`: every item of the upstream README TODO lists (282)
  with upstream state and what this fork did / where it's tracked; upstream missions matched to sweep results.
- Sweep `$MissionPrep`: per-mission real-play setup before `startmission` (Lowrider High Stakes needs CJ in a lowrider).
- `testing/make-friend-package.ps1`: zip for friends (`friend-package/`): our client/proxy/launcher/scm, server,
  install/uninstall.bat (renames THEIR eax.dll, moves CLEO+ out), README (testing/friend-README.txt), GPL LICENSE +
  our patches vs upstream df03bbf. Never put game files in it. Rebuild it after every deploy; everyone must use the same build.
- `testing/test-local.ps1 -Instances 1 -Bots 3`: manual play with bots near Grove Street (start the game first so it is host).
- Test copies (use these while someone plays the real game): `testing/make-test-copies.ps1` makes
  "GTA San Andreas (test)" and "(test) (partner)"; then `build.ps1 -Deploy -GameDir`, `build-scm.ps1 -GameDir`.
  On them: `quick-fixes.ps1` (12 play-reported bugs, ~6 min), `alttab-repro.ps1` (focus loss during a cutscene,
  then W must walk; `-NoAltTab` control, `-Only 1C,8` single messages), `perf-probe.ps1` (status `coopUs`: coop's
  own per-frame microseconds by section), `barber-solo.ps1` (one game gets the barber chair),
  `gap-probe.ps1 -Missions "16,22"` (host-run missions: blips/markers/checkpoints/fires/pickups host vs partner, money
  after the mission's own pass), `markers-test.ps1` (checkpoints, mission pickup, mission fire, train), `car-jitter.ps1`
  (partner via the lag simulator: car back-steps old vs smooth, end position, trailer), `train-test.ps1`,
  `side-jobs.ps1` (taxi/vigilante/paramedic/firefighter for host and partner). Test games write `hang.txt` (main
  thread stack) when the game loop stops for 8 s. CrashInfo.SA.asi is renamed `.off-for-tests` in the test copies so
  CoopAndreas' own crash log (with a backtrace) is written; resolve CoopAndreasSA.dll offsets with
  `CoopAndreas/build/CoopAndreasSA.map`. Keep test players out of the sea (x 1200 at the airport is water).
  Test games keep saves/settings/user tracks in `%TEMP%\coopt-<autodir>` (never the real Documents; every test that
  writes there must also check the real folder is unchanged). `save-sync.ps1`, `tracks-test.ps1` (+ passenger radio),
  `crash-test.ps1 [-GameDir]` (deliberate crash: closes quietly, log written), `midsession-load.ps1`, `boot-check.ps1`.
  Test cleanups must use Remove-Item -Recurse -Force -Confirm:$false (a prompt hangs the run).
  Bug hunting: `soak-test.ps1 -Minutes 20 -Seed N` (host + partner via the lag simulator, random actions, the
  report's actions.txt), then `replay.ps1 -Actions <actions.txt> [-Skip '3,5-9']` replays it with the same timing to
  reproduce and narrow down a crash. `cutscene-death.ps1` (deaths in cutscenes, mission start with a dead partner),
  `solo-mission.ps1`, `probe-all.ps1` (all story missions with 2 players). Test-only commands must not create
  states real play can't (healing a dying player broke the restart and looked like a game bug). `kill` is a real
  deadly hit (ignored in cutscenes and no-control scenes, like the game), `kill hard` only zeroes health. After a
  death use `Wait-Playable { Status 'partner' }`: the first death plays the ~25 s hospital tutorial.
  coop-anything toolkit (`toolkit-coop-anything/`, Python via `py -3 -I`): `chaos-test.ps1 [-Profiles ...]` (partner
  through the toolkit's chaos relay, good_wifi..hell, outages), `anim-sync.ps1 [-RebuildHost|-RebuildPartner]`
  (probe + animcheck; profile from `testing/animcheck/make-profile.ps1`), `usertrack-hang.ps1`. Never capture
  screens (the game's JPEG writer grabbed the real desktop); check visuals through probes.
  `collectibles.ps1 [-Collector host]`, `rejoin.ps1`, `gang-recruits.ps1`; `post-discord.ps1 -File <log>` posts
  progress to the owner's Discord at milestones (webhook in `.discord-webhook`, never commit or print it).
  `pool-probe.ps1 [-Repeat 3]` (collision-model pool growth per action; status `pools`), `car-death.ps1`,
  `respawn-health.ps1`, `barber-pair.ps1 [-KillFirst|-KillInMission]`. A crash in .HOODLUM code (0x1556000+) is a
  game function the crack moved: decode it from the exe bytes (raw = 0xD96A00 + va - 0x1556000), and read the
  crash log's Pools section first.

### Autotest mode (client/src/CAutoTest.*)
Only active with `--autotest`. It writes `GTA San Andreas/CoopAndreas/autotest/`:
- `events.jsonl`: one JSON per line `{"t":tick,"ev":...}`. Events: boot, hook_reclaimed, menu_new_game, menu_resume,
  game_loop_running, connected/disconnected, authenticated, host_gained/lost, player_joined, player_ped_created,
  player_left, chat_received, command, vehicle_entered/exited, interior, wasted/alive,
  mission_started/ended, mission_passed/failed (M_PASS*/M_FAIL big message on screen), cutscene_started/ended
  (with skipped), skip_vote_state (votes/voters). `-autodir <sub>` separates files per game instance.
- Bot extras: `--stand X Y Z`, `--vote-skip`; it prints a `MISSION {json}` line whenever mission traffic arrives.
- `status.json` (every 500 ms): connection, measured fps, focus, local player, every network player with position/distance, chat, commands.
- `commands.txt`: append one command per line; it is polled at 10 Hz.
Add a new event wherever a feature needs verifying, then assert on it in lab.ps1. Don't add screenshots.
- Bots: `CoopAndreasBot.exe --host IP --port P --name N --duration S [--expect-peers N] [--expect-refused] [--no-chat]`;
  prints `RESULT {json}`. Exit code 0 pass, 1 fail, 2 could not connect.

## Rules for agents
- Log every change to the game folder or the fork in MODLOG.md (date, what, why, how to undo).
- Do not delete game files; back up into `backup-original/` first.
- Game addresses are 1.0 US (`PLUGIN_SGV_10US`). Verify any new address against `gta_sa.pdb`/plugin-sdk, or with REA/Ghidra before using it.
- Player cap: `server-config.ini` `maxplayers` (default `Config::DEFAULT_SERVER_PLAYERS` = 4, hard cap `MAX_SERVER_PLAYERS` = 8).
- Our fork lives on branch `coop4` in `CoopAndreas/`. Rebase it on upstream `main` to pick up new mission sync work.
- The client sends crash logs to the CoopAndreas devs by default (`report-crashlogs=true` in `coopandreas.ini`).
- Prefer upstream-compatible changes; keep diffs small so we can rebase on Tornamic/CoopAndreas.
- Test before claiming it works: `testing/run-tests.ps1` (headless bots) and then a real in-game session.
- Bugs reported from play: reproduce/check each with a short targeted test (`testing/quick-fixes.ps1`, ~5 min,
  add a section per bug) instead of hour-long sweeps. Test games run hidden unless the user asks to see them.
- The user may be playing the real game while you work: test in the copies made by `testing/make-test-copies.ps1`
  ("GTA San Andreas (test)" + "(test) (partner)"), deploy with `-GameDir`, use 167xx ports, and never stop a
  gta_sa.exe that isn't from your copy (lab.ps1, lab-duo.ps1, playthrough.ps1, jitter-tune.ps1 and
  mission-sweep-parallel.ps1 still kill every gta_sa.exe - don't run them while someone plays).
- New script commands: add them to `sa_coop.json` AND `sa_coop.db` and write them as `Coop.X(...)`; build-scm.ps1
  syncs both into Sanny's folder. A raw `not 1D21:` line compiled to nothing.
- Report fixes to the user as a table **Bug | Cause | Fix | Tested** in plain player language (Tested: ✅ with the
  concrete result, ⚠️ when not testable automatically), then a short "Still open" list and which zip to send
  friends. The user asked to keep this style.

## Missions in coop (details: MISSIONS.md, overview of the build: MISSION-COOP-BUILD.md)
- Cutscenes/widescreen scenes hide the other players' CJs (`CCutscenePlayerHider`), name tags were already hidden.
- Sweeps end missions with `fail_current_mission` by default (`-EndBy death` to kill the host instead) and set max
  wanted level 0 (`nowanted`): a fresh save has SF/LV locked, so later missions gave CJ 4 stars every time.
- Host runs the mission script; partners follow. 7 story missions are ported upstream (Coop.* commands in scm/scripts:
  INTRO1, INTRO2, SWEET1, SWEET1B, SWEET3, TWAR7, SMOKE2). All others run host-driven.
- Our fallback (`COpCodeSync.cpp` `IsUnportedMissionFallbackOpcode`): for unported mission scripts on the host, sync
  print/print_now/print_big/print_with_number_big/print_help/clear_prints, load_mission_text, register_mission_passed,
  do_fade, switch_widescreen, load/start/clear_cutscene. Ported scripts keep their own per-player print_now/print.
  Also for unported missions: money/wanted level shared (add_score/alter_wanted_level/clear_wanted_level on `$player1`
  replayed on each client's own player), identical print/print_now/print_help keys de-duplicated (2 s), and partners
  more than 50 m away are teleported next to the host when a mission starts or the script moves the host
  (`CCommandTeleportPlayersToHostSafely::RequestFarPartnersTeleport`, max once per 5 s, not during cutscenes/in cars).
- **Partner vehicles** (`client/src/CMissionPartnerVehicles.*`, host only, all missions): when the host is in a
  mission vehicle (car/bike/BMX/quad/monster truck) whose free seats can't hold the nearby partners (story NPCs fill
  them), copies of it are spawned behind it (max 3, friendly blip, chat note, event `partner_vehicles`), and released
  when the mission ends. Re-checked every second because NPCs board after the host. Verified: Ryder 2, Drive-Thru 1,
  Drive-By 1.
- Porting a mission properly = edit its `scm/scripts/<LABEL>.txt` like SWEET1.txt: `Coop.EnableSyncingThisScript()`,
  `$NETWORK_PLAYER[0..2] = Coop.CollectNetworkPlayersForTheMission()`, `Coop.TeleportPlayersToHostSafely()`, per-player
  texts (`Coop.PrintNowForNetworkPlayer`), blips (`Coop.SetBlipVisibleTo`), checkpoints, trigger with
  `Coop.LocateAllPlayersOnFoot3D`. Then `testing/build-scm.ps1` (Sanny Builder 4.2 in C:\Tools\SannyBuilder4, mode
  sa_sbl_coopandreas; unmodified sources compile byte-identical) and run the sweep for that mission.
- `testing/lab-duo.ps1 [-Mission 16]`: two real games (host + partner, `-autodir host|partner`) for what bots can't
  show: the partner's own cutscene, vote, MISSION FAILED banner, money/wanted after the mission. 14 checks.
  The partner runs from `GTA San Andreas (partner)`, a hard-link mirror made by `testing/make-partner-copy.ps1`
  (re-run after every deploy). Reason: modloader.asi crashes (+0xA34E after "Parsing command line") when another
  game instance is already running, so the partner copy has modloader removed and the _ESSENTIALS ASIs in scripts\.
  Both games keep ~75 fps unfocused (CoopAndreas forces ForegroundApp).
- A mission started a few seconds after a new game can crash SilentPatch's audio stream thread on the first cutscene
  (silentpatchsa.asi+0xAAC0); the sweep waits 15 s after boot. Real players reach a marker much later.

## Sync backlog (what still needs syncing; keep this list current)
From upstream README TODO (unchecked) plus what our lab/sweep found. Mark items done here and in MODLOG.md.
- [x] Mission pickups (2026-10-25, CMissionPickupSync): pickups a mission creates after it starts are copied to partners;
      a partner collecting one makes the host's count as collected. markers-test.ps1.
- [ ] Pickups: collectibles (tags/horseshoes/snapshots/oysters), static weapons/armour/bribes, dropped money/weapons
      stay per player (each player has their own)
- [ ] Jetpack pickup (flight is synced)
- [x] Cutscenes + vote to skip (upstream code exists; verified 4/4 by our lab, incl. unported missions via fallback)
- [x] Gang territories (2026-10-25, CGangZoneSync): zone strengths/colours from the host. Gang wars themselves still
      run in each game (a partner starting a war: untested)
- [x] Saves (CSaveSync): everyone gets the host's save in the slot anyone saved; own look per player (.coop file)
- [x] User tracks shared (CUserTrackSync); passengers follow the driver's station (slow to start, see MODLOG)
- [ ] Map: player map pin proportions
- [ ] Wanted level (tag `wanted`)
- [x] Mission money: rewards of host-run missions go to every player (ADD_SCORE fallback; gap-probe.ps1 shows the same
      amount on host and partner, e.g. 200/200, 8000/8000, 20000/20000)
- [ ] Stats: breath bar, max HP
- [x] Mission fires (2026-10-25, CMissionFireSync): spot fires of the host's mission burn for partners too; a partner
      putting one out puts the host's out. Fires on burning cars/peds follow their entity.
- [ ] Cheat codes
- [ ] Animations: idle anims, TAB+NUM4/6 anims
- [ ] Gang groups / recruits (tag `gang-group`): mission gang members follow the host (the script puts them in the
      host's group); free-roam recruiting is per player
- [ ] Stream in/out of players, peds, vehicles (green polygon model loading)
- [x] Trailers (2026-10-25): VehicleDriverUpdate.trailerId; partners SetTowLink the trailer (car-jitter.ps1)
- [x] Trains (2026-10-25, CMissionTrainSync): every train the host creates (mission + random) is built on partners on
      the host's node/track and kept at the host's rail distance and speed (train-test.ps1)
- [ ] Vehicles: forced hydraulics, gamepad for passengers
- [ ] Widescreen fix interaction
- [x] NPC jitter (friends 2026-10-23): synced on-foot peds snapped to every update (20/s) while their local AI moved
      them in between. Now CNetworkPedManager::Process glides them to (last synced pos + velocity x age, <=200 ms),
      closing 25% of the gap per 50 fps frame; height left to local physics unless >1 m off; snap only >6 m.
      Measured (testing/jitter-tune.ps1): moving frames where an NPC steps backwards 5.7-7.3% -> 0% (natural 0%);
      strength 0.4 overcorrects (5%).
- [x] Cars driven by other players glide (2026-10-25, CNetworkVehicleManager::ProcessSmoothing): never pulled back
      along their direction of travel; over a 60+-20 ms link back-steps 2-7% -> 0% (car-jitter.ps1). Parked/NPC cars
      (idle updates) still snap; rotation is set directly.
- [x] Alt-tab freeze: the Widescreen Fix opened the pause menu on focus regain; closed by CloseFocusPauseMenu
- [x] Partner respawn mid-mission: ported missions fail for everyone when a partner dies (checked); if one ever goes
      on, 1D02's globals are switched to the respawned ped (CCommandCollectNetworkPlayersForTheMission)
- [ ] NPC sync: in-vehicle horn/siren, aim, shots, task sync
- [ ] Player voice commands, chat reactions, chat gamepad support
- [ ] Gang wars (tag `gang-wars`), parachute jumps (tag `parachute`), stunt bonuses + slow motion
- [ ] Laser sniper red dot
- [x] Side jobs: taxi, vigilante, paramedic, firefighter start for the host and for partners, each on their own game
      (side-jobs.ps1)
- [ ] Missions: ~95 story missions not ported (see MISSIONS.md; host-run, partners now get the markers, checkpoints,
      pickups, fires, objects, trains and money of them), sub-missions pimp, freight, hidden races (BMX, NRG-500, Chiliad), stadiums (8-Track, Blood Bowl, Dirt Track,
      Kickstart), Ammu-Nation challenge, schools, property purchase
- [x] Race checkpoints and "go here" markers of host-run missions (2026-10-25, CMissionMarkerSync, markers-test.ps1)
- [x] (fixed by the shim below; 2 full Big Smoke+Ryder playthroughs + lab since, no crash) Host crash in script delete_char (009B) -> CTheScripts::RemoveThisPed -> CWorld::RemoveReferencesToDeletedObject
      (end of Big Smoke 05:48, leaving the barber in Ryder 06:40; testing/reports/play-crash-*): the vehicle-pool loop
      calls vtable+0xA0 of a USED slot holding a destroyed vehicle (vtable 0x863C40 = CPlaceable, +0xA0 = text
      "cles"). Same root as the bad-link crash: the vehicle deleting destructors (`push esi; mov esi,ecx; call ~X;
      push esi; call operator delete`, 10 classes) call operator delete(nullptr) — logged by the delete guard with
      exactly those callers (0x6B1345 CAutomobile, 0x6B8965 CBike) — so the destructor chain returns with ESI = 0
      (a callee breaking callee-saved ESI; CVehicle::~CVehicle calls SilentPatch +0xA4D0 at 0x6E2B6E and our
      CRadar__ClearBlipForEntity_Hook at 0x6E2BB2). Fix in Hooks/VehicleHooks.cpp: VehicleDtorShim around the
      destructor call keeps ESI (status `dtorEsiClobbered` counts repairs). Verify with playthroughs, then find the
      ESI clobberer itself.
- [x] Big Smoke + Ryder played to MISSION PASSED by 2 real games (testing/playthrough.ps1, no shortcut)
- [ ] Pass sweep (4 players, own pass routine; MISSIONS.md column "Pass"): 63/102 passed with the banner on all
      partners. The 2026-10-23 12:19 rerun was stopped by the user at ~53 missions, so most odd ids >= 73 still show
      the stale first-sweep result ("no debug-pass check reached"): rerun `mission-sweep-parallel.ps1 -EndBy pass
      -Missions "<those ids>"`. Missions whose debug check sits in a late stage (races CPRACE, Lowrider CESAR1,
      dates CATALIN, flight school DESERT5...): 89 story missions now carry a 1D20 pass label (`add-pass-labels.ps1
      -All`, committed, NOT deployed yet - run testing\build-scm.ps1 before the next sweep). No label (no
      RegisterMissionPassed in the script): CESAR1, CATALIN, CATCUT, FINALEA, FINALEB - pick their pass labels by hand.
- [x] (2026-10-25: starts and passes with 2 players, gap-probe.ps1) CAT1 (41, Local Liquor Store): the host game exited ~1 s after `startmission 41` (players_hidden = its opening
      scene), no crash log (hard exit, not caught by CCrashLog/CrashInfo) - repro with lab.ps1 -Keep + lab-cmd
      "startmission 41". In real play Catalina's first mission starts from her marker after the phone call.
- [x] (2026-10-25: starts and passes with 2 players) CATCUT (45, King in Exile): the game stops answering commands right after `startmission 45` (both sweeps;
      TRUTH2 47 "did not answer" was only the next mission). CATCUT is cutscene-only and normally runs after the
      Catalina missions - check whether launching it directly hangs single player too, else it's coop-specific.
      Script: RegisterMissionGiven, `Streaming.SetAreaVisible(2)`, `Cutscene.Load('BCESAR2')`, wait HasLoaded - no
      cutscene_started was logged and commands stopped (a waiting script would not block them), so the game hangs in
      the cutscene load with area 2 visible while the player stands outside. CAT1's opening (fade, decision makers,
      debug-key loop) has nothing unusual - its exit needs a live repro.
- [ ] Missions 3-10 (Tagging Up Turf .. Los Sepulcros) only verified by the sweep (start, cutscenes, pass routine,
      banners for 4 players): extend testing/playthrough.ps1 (spray tags, fights, drive-by) or have people play them.
- [ ] Extend playthrough.ps1 to the next missions (Tagging Up Turf, Cleaning the Hood, Drive-Thru...): spray tags,
      gang fights and chases need new autopilot actions (aim/shoot, drive-by)
- [ ] Remote player's area code on partners: status players[].interior of the host stayed stale on the partner across
      shop doors (driver now uses the host's own status) - check what a real partner sees
- [x] Partner markers/blips in unported missions: markers, checkpoints, pickups, fires, objects (WorldHooks creates
      network objects for unported mission scripts too) and trains are mirrored; gap-probe.ps1 compares host and partner
      per mission. Blips on mission peds/cars appear on partners a moment later (network peds/cars arrive later).
- [ ] Mission pass verified with 4 real players (sweep only fails missions; needs a human playtest)
- [x] Crash on a partner over a very bad link (150±40 ms, 5% loss): vehicle ctor writing to 0x320530/0x8D530/0x23B530.
      Root cause: the game calls `CVehicle::operator delete(nullptr)` (callers gta_sa 0x6B1345, 0x6B8965) and the
      original 0x6E2D90 has no null check: slot index = (0 - m_pObjects)/0xA18 becomes the pool's next-free index
      (huge negative), so the next vehicle (network or traffic) is built outside the pool. Fixed by a guard on 0x6E2D90
      (Hooks/VehicleHooks.cpp: refuses null/non-slot/free-slot pointers, event `vehicle_delete_refused`) + an index
      repair before CNetworkVehicle::CreateVehicle (event `vehicle_pool_repaired`). 9 harsh runs since: no crash.
- [ ] Real play across two PCs (all tests are on one PC; netsim approximates it)

## Known mod conflicts (handled)
- CLEO 4.4 takes over the CGame::Process call at 0x53E981 without chaining, so all per-frame coop code
  stopped: players connected but never finished the handshake. `CPatch::ReclaimGameProcessHook()` takes it back
  (CLEO scripts don't run in coop; coop uses its own main.scm). Event `hook_reclaimed`.
- SilentPatch loaded from modloader was missed by CoopAndreas' detection, which crashed at 0x748731. Fixed in `IsSilentPatchInstalled()`.
- CLEO+ is refused by CoopAndreas; it is moved to `disabled-mods/`.

## Known risks with the Essentials pack
- CoopAndreas patches the framerate itself (`CPatch::PatchFramerate`), so it may fight Framerate Vigilante.
- CoopAndreas ships its own `main.scm`. CLEO scripts that assume the stock story script may break in coop.
- Windowed Mode and Widescreen Fix are usually fine, but disable them first if the client crashes on start.
