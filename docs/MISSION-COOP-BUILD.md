# Mission coop build: what was added, how it works, results

Fork: `CoopAndreas/` branch `coop4` (on top of Tornamic/CoopAndreas `df03bbf`, v0.3.0-alpha).
Per-mission status table: [MISSIONS.md](MISSIONS.md). Sync backlog and rules: [AGENTS.md](AGENTS.md). Change log: [MODLOG.md](MODLOG.md).

## 1. Starting point (upstream)
- The **host** (first player on the server) runs the story script; other players are **partners**.
- Upstream ported **7 story missions** for coop (per-player texts, blips, checkpoints, teleports via `Coop.*` script
  commands): Big Smoke, Ryder, Tagging Up Turf, Cleaning The Hood, Drive-Thru, OG Loc, Running Dog.
- The other ~95 missions ran **host-only**: partners got no objectives, no MISSION PASSED/FAILED banner, never saw the
  cutscenes and therefore could never vote, so the host could never skip a cutscene (the vote needs every player).

## 2. What this build adds for missions

| Feature | Where | What it does |
|---|---|---|
| Unported-mission fallback sync | `client/src/COpCodeSync.cpp` (`IsUnportedMissionFallbackOpcode`) | For mission scripts without `Coop.EnableSyncingThisScript`, the host sends texts (print, print_now, print_big, print_with_number_big, print_help, clear_prints), `load_mission_text`, `register_mission_passed`, fades, widescreen and cutscenes (load/start/clear) to all players. Partners see objectives, banners and cutscenes and can vote to skip. |
| Shared money + wanted level | same file (`IsSharedPlayerOpcode`) | In unported missions, `add_score`, `alter_wanted_level(_no_drop)`, `clear_wanted_level` on the host's player are replayed on each client's own player: everyone gets the reward and the heat. |
| Text de-duplication | same file, `BuildAndSendOpcode` | Identical print/print_now/print_help keys are sent once per 2 s (some scripts print every frame; one sent 235 texts). |
| Far-partner teleport | `Commands/Commands/CCommandTeleportPlayersToHostSafely.*`, `Main.cpp` | Partners more than 50 m away are moved next to the host (safe spot search) when a mission starts or an unported script moves the host. Max once per 5 s, never during cutscenes or while the host is in a car. |
| Extra cars for partners | `client/src/CMissionPartnerVehicles.*` | When the host is in a mission vehicle (car, bike, BMX, quad, monster truck) and NPCs (Sweet, Smoke, Ryder…) leave too few seats for the partners nearby, copies of the vehicle spawn behind it (max 3, friendly blip, chat note) and are released after the mission. |
| Hide other CJs in cutscenes | `client/src/CCutscenePlayerHider.*` | During cutscenes and scripted widescreen scenes the other players' peds are made invisible (everyone is CJ), restored afterwards. Name tags were already hidden. |
| Friendlier notice | 6 scripts (RYDER2, RYDER3, SMOKE3, SWEET2, SWEET4, SWEET6) | "Unsupported, not recommended" replaced by "host drives it; partners get texts, cutscenes, money and wanted level". |
| Crash fixes on the way | `CPatch.cpp` | SilentPatch-in-modloader detection (startup crash 0x748731); CLEO 4.4 stealing the per-frame hook (nothing synced in game). |

## 3. Test tooling built for missions
| Tool | Purpose |
|---|---|
| `client/src/CAutoTest.*` (`--autotest`) | Game logs events (`events.jsonl`), live `status.json`, takes commands. Mission events: `mission_started/script/ended/passed/failed`, `cutscene_started/ended`, `skip_vote_state`, `partner_vehicles`, `players_hidden/shown`. Commands: `startmission <id>`, `failmission`, `entermissioncar`, `skipcutscene`, `nowanted`, `kill`, `teleport`, `vehicle`, `chat`… |
| `testbot` (`CoopAndreasBot.exe`) | Fake partner: `--stand` in a marker, `--vote-skip`, follows scripted teleports, logs every mission packet it receives (on-mission flags, cutscene opcodes, texts, banners, votes). |
| `testing/lab.ps1 -Scenario mission` | Big Smoke with a partner: all-players marker trigger, INTRO1A/INTRO1B vote skip, fail, respawn, what the partner received, CJs hidden in the cutscene. |
| `testing/lab-duo.ps1` | Two **real** games (host + partner copy): partner sees the cutscene, votes, gets the banner and objective blips. 14/14. |
| `testing/mission-sweep.ps1` | 4 players (host + 3 bots) through every mission: start, skip all cutscenes 4/4, get into the mission car, end it, record what partners got. `-EndBy fail` (default, `fail_current_mission`, CJ stays alive) or `death`. |
| `testing/mission-sweep-parallel.ps1` | Two sweeps at once (normal install + partner copy, separate ports) to halve the time. |
| `testing/mission-catalog.ps1` | Rebuilds MISSIONS.md from the scripts + newest sweep result per mission. |
| `testing/build-scm.ps1` | Compiles the mission scripts (`scm/main.txt`) with Sanny Builder 4.2; unmodified sources = byte-identical to the shipped `main.scm`. Needed to port missions properly. |
| `testing/resolve-crash.ps1` | `CoopAndreasSA.dll+0x...` from a crash log → function name (link map). |

## 4b. Final results (2026-10-22 23:40)
- **102 of 102 story missions clean with 4 players** in the sweep. Lowrider (High Stakes) works when started like in
  real play (CJ in a lowrider — sweep `$MissionPrep`); Monster and Home Coming passed twice more after the
  skip-input fix (their earlier "cutscene stuck" came from real mouse/keyboard input being counted as a host vote).
- Internet-like test (`lab-duo.ps1 -Net`, partner through the network simulator): 75±15 ms one-way + 2% loss →
  15/15. Very bad link 150±40 ms + 5% loss: the old vehicle-constructor crash (a null vehicle delete corrupting the pool) is fixed; 9 runs without a crash.
- Upstream comparison: UPSTREAM-SYNC-CHECKLIST.md (all 282 upstream TODO items, mapped).
- The unported-mission chat notice is now a neutral "[CoopAndreas] Host-driven mission…" info line.

## 4a. Latest results (newest build, parallel sweep + reruns, 2026-10-22 23:20)
- **101 of 102 story missions clean with 4 players** (start, every cutscene skipped by a 4/4 vote, mission ends,
  partners got the start/end, texts and blips, no crash). Missions are ended with `fail_current_mission`, which
  doesn't print a MISSION FAILED banner (the death path in the lab does, and partners get it).
- The only open one: **Lowrider (High Stakes)** (36): the game closes right after the script starts when launched
  directly on a fresh save with CJ on foot (in real play you start it at the meet, in a lowrider; hydraulics are
  unsynced upstream). Needs a real-play test.
- Fixed since the first sweep: the 4 "did not start" (startmission now sets `$onmission` like the triggers),
  missions launched on top of a still-running minigame (sweep restarts the game; startmission refuses while code runs
  in the mission block — crash gta_sa+0x6952A), the SilentPatch crashes did not reappear in this run's reruns.
- Lab 34/34, duo 15/15 on this build. Full parallel sweep of 102 missions: ~40 min (was ~1 h 45 min).

## 4. Results (4 players, first full sweep of story missions 11–112)
- **102 swept, 86 clean**: start, every cutscene skipped by a 4/4 vote, mission ends, partners got start/end,
  texts and the fail banner, no crash.
- **8 did not end on host death** (races/minigames and a few story missions handle death differently):
  OG Loc, House Party, Race Tournament, Lowrider High Stakes, Local Liquor Store, King in Exile, Wu Zi Mu, Test Drive.
  Newer sweep ends these with `fail_current_mission`.
- **4 crashed, all the same SilentPatch audio-thread crash** (`silentpatchsa.asi+0xAAC0`): Snail Trail, Stowaway,
  High Noon, Vertical Bird. It happens on a cutscene/mission start shortly after the game (re)started; the faulting
  instruction is the first of a SilentPatch function, i.e. the module was unloaded under a running thread.
  Not seen when a mission starts later in a session. Open item.
- **4 "did not start"** (no on-mission flag within 12 s): Ran Fa Li, Ice Cold Killa, Black Project, Grove 4 Life.
  Cause found: these scripts set `$onmission = 1` late (FARLIE4 line 78, SYND4 line 671) or rely on the marker
  trigger setting it before launch (like INT.txt does). The test command `startmission` skipped that step, so it's a
  harness bug, not a mission bug — real triggers set the flag. Fixed: `startmission` now sets `$onmission = 1`
  first (built, needs a re-sweep). Ran Fa Li's script also kept running and blocked later missions until
  `failmission` was added.
- Partner cars spawned in: Ryder (2), Drive-Thru, Drive-By, Customs Fast Track, Puncture Wounds (1 each).
- Test artefact, not a coop bug: launching San Fierro/Las Venturas missions on a fresh save puts CJ in still-locked
  cities → instant 4-star wanted level. The sweep now sets max wanted level 0 (`nowanted`).

## 5. Not verified yet (needs people or more work)
- **Passing** missions with 4 real players (the sweep only fails them).
- Online play between different PCs (all tests are on one PC).
- Deploy + lab run of the newest build (cutscene CJ hiding, objective-blip check, `nowanted`): built, not yet run.
- Per-mission ports (partner-specific objectives/checkpoints in unported missions), pickups, gang groups, fire,
  trains/trailers: see the sync backlog in AGENTS.md.

## 6. How to rebuild and retest
```
powershell -ExecutionPolicy Bypass -File testing\build.ps1 -Deploy        # client, server, proxy, launcher, bot
powershell -ExecutionPolicy Bypass -File testing\build-scm.ps1            # mission scripts (after editing scm/)
powershell -ExecutionPolicy Bypass -File testing\make-partner-copy.ps1    # refresh the 2nd game folder
powershell -ExecutionPolicy Bypass -File testing\run-tests.ps1            # headless, 8 checks
powershell -ExecutionPolicy Bypass -File testing\lab.ps1                  # real game + bots, basic + mission
powershell -ExecutionPolicy Bypass -File testing\lab-duo.ps1              # two real games
powershell -ExecutionPolicy Bypass -File testing\mission-sweep-parallel.ps1 -Missions "11-112"
powershell -ExecutionPolicy Bypass -File testing\mission-catalog.ps1      # refresh MISSIONS.md
```
