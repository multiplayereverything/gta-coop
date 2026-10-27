GTA San Andreas co-op 1.0.0 (based on CoopAndreas) - up to 4 players
==================================================================

Expect some bugs, save often. Everyone must use THIS package (same build).

WHAT YOU NEED
- Your own GTA San Andreas, version 1.0 US. Steam/Rockstar Launcher versions must be downgraded to 1.0 first
  (search "GTA SA downgrader"). This package contains no game files.
- DirectX End-User Runtime (June 2010) if the game says d3dx9_43.dll is missing.

INSTALL (everyone)
1. Copy everything from the "game" folder into your GTA San Andreas folder (next to gta_sa.exe).
2. Run install.bat there once. (uninstall.bat puts everything back.)
   No serial key needed: this build starts straight into coop.

HOST (one person)
1. Run server\server.exe and keep it open (port 6767, max 4 players, see server-config.ini).
2. Let your friends reach you, EITHER
   - forward UDP port 6767 on your router to your PC and give them your public IP, OR
   - all install a VPN like Tailscale / ZeroTier / Radmin VPN and use the host's VPN IP (easiest).
3. Allow server.exe in Windows Firewall when asked.

JOIN (everyone, host too)
LaunchCoopAndreas.exe (opens the game in coop) -> Start Game -> nickname, IP (host: 127.0.0.1), port 6767 -> Connect.
The host must join first: the first player in runs the story.

PLAYING MISSIONS TOGETHER
- The host runs the story. Some missions are fully coop; for the others the host drives the mission and everyone
  else gets the objectives, cutscenes, MISSION PASSED/FAILED, money and wanted level.
- Anyone can start a mission: walk into its marker (or type /mission <name>). The host's game starts it and the
  host is moved to the marker.
- Cutscenes: everyone presses the skip key; it skips at N/N votes.
- No seat in the mission car? An extra copy of the car spawns behind it for you (green blip).
- Got a vehicle with a blip of your own (BMX in Big Smoke, Greenwood in Ryder)? Use it - don't take the mission
  character's seat in the host's car, or the mission waits for him.
- "Everyone in the marker" checkpoints wait for ALL players: stay near the host and the blue-blipped characters.
- Between missions follow the game's hints (after Big Smoke the host goes into CJ's house and out again).
- Far away when a mission starts? You get teleported to the host.
- Don't start a mission in the first seconds after the game loads (rare crash) - walk to the marker first.

SHARED BETWEEN PLAYERS
Missions (objectives, markers, checkpoints, pickups, fires, trains, cutscenes, rewards), money, saves (everyone keeps
their own look), gang territories and recruits, oysters/horseshoes/snapshots, sprayed tags, phone calls (ring, voice
and subtitles), your User Tracks songs.

CHAT COMMANDS (F6, then type; /help lists them)
/players, /tp <name>, /bring <name>, /goto x y z, /pos, /mission <name or number>, /missions, /fail, /skip,
/heal, /car <name>, /gun <weapon id> [ammo], /time <hour> and /weather <id> (host), /report <what happened>.

IF SOMETHING GOES WRONG
- Type /report what happened  in the chat (F6). It saves CoopAndreas_reports\report-<time>.txt in your GTA folder
  with the mission, place, players and connection. Send that file, plus the newest file in CoopAndreas_crashes if
  the game crashed, to whoever runs your group's build.
- A crash closes the game quietly and writes a crash log to CoopAndreas_crashes. (The original CoopAndreas code also
  sends that log to the CoopAndreas author's server.)
- A friend's name says "(connection lost)": their game or connection is gone. They can start the game and join
  again right away; the session keeps going.
- A Wi-Fi hiccup of up to ~30 s does not throw you out.

KNOWN LIMITS
Gang wars, property purchases, stunt jumps and minigames (pool, basketball, dancing, casino) are each player's own.
Mods: CLEO+ breaks shot sync (install.bat moves it out). Other mods may conflict - try without them first.
