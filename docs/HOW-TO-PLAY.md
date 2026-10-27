# Playing GTA SA coop with friends (up to 4)

## One-time setup (everyone)
1. Everyone needs their **own** GTA San Andreas **PC 1.0 US** (don't share your game folder) plus the same coop build:
   send friends `coop-dev\friend-package\CoopAndreas-coop4-<date>.zip` (made by `testing\make-friend-package.ps1`,
   ~2.4 MB, no game files). They copy `game\*` into their GTA folder and run `install.bat` once; the zip's
   README.txt walks them through the rest. `uninstall.bat` undoes it.
2. No serial key: this fork removed the upstream beta key check, `LaunchCoopAndreas.exe` starts the game in coop.

## Host (one person)
1. Run `coop-dev\server\server.exe` and leave the window open. `server-config.ini` next to it has `port = 6767` and `maxplayers = 4`.
2. Let friends reach you, using either:
   - a router port-forward of **UDP 6767** to your PC, giving friends your public IP, or
   - a VPN LAN such as Tailscale, ZeroTier or Radmin VPN, giving friends your VPN IP (easier, no router changes).
3. Allow `server.exe` through Windows Firewall when it asks.

## Join (everyone, including the host)
1. Run `LaunchCoopAndreas.exe` (it opens the game in coop mode).
2. Start Game → enter a nickname, the host's IP (host uses `127.0.0.1`) and port `6767` → Connect.
3. Join the host first. The first player in runs the world (peds, traffic, missions).

## Missions together
- The host (first player who joined) runs the story, but ANY player can start a mission: step into its marker (or
  type `/mission <name>`) and the host's game starts it there, moving the host to the marker; everyone far away is
  brought along. For ported missions everyone nearby must stand in the mission marker.
- Unported missions show "This mission is currently unsupported": the host starts and plays them, everyone else sees
  the objectives, cutscenes, MISSION PASSED/FAILED banner, and shares the money reward and wanted level.
- Cutscenes: everyone presses the skip key; it skips when the counter shows N/N.
- No seat left in the mission car (Sweet, Smoke and Ryder took them)? The host's game spawns an extra copy of the
  car behind it for the partners (green blip, chat note). It disappears after the mission.
- Partners far away when a mission starts (or when the mission moves the host) are teleported next to the host.
- Partners: when your screen shows a vehicle of your own with a blip (your BMX in Big Smoke, a Greenwood in Ryder),
  take that one. Don't sit in the host's mission car: the seat may be the mission character's (Ryder can't get into
  his car if a partner sits there, and the mission waits for him).
- Checkpoints like "everyone at the red marker" wait for ALL players: stay close to the host and the blue-blipped
  characters (Sweet, Ryder); an AI rider nobody is near may stop and wait.
- Between missions do what the game says (after Big Smoke: "Go inside CJ's house to continue" - the host walks into
  the house and out again, then Ryder's marker appears).
- Status of every mission: `coop-dev\MISSIONS.md`.
- Don't start a mission in the first seconds after a new game loads (rare audio crash); walk to the marker first.

## Chat commands (F6, then type)
- `/help` lists them. `/players` shows everyone with their number.
- `/tp <name or number>` takes you to that player, `/bring <name or number>` brings them to you, `/goto x y z`,
  `/pos` shows where you are.
- `/mission <name or number>` starts a story mission (`/missions` lists them), `/fail` fails the running mission
  (host), `/skip` votes to skip a cutscene.
- `/heal`, `/car <name or id>` (e.g. `/car infernus`), `/gun <weapon id> [ammo]`, `/time <hour>` and
  `/weather <id>` (host; everyone follows the host's clock and weather).
- Debug menu: type the cheat `D1212`, tick Missions, and click one to start it.

## If something goes wrong
- Chat (F6): `/report what happened` saves `CoopAndreas_reports\report-<time>.txt` in the game folder (mission,
  place, players, connection, newest crash log name). Send it with the newest `CoopAndreas_crashes\*.log`.
- "(connection lost)" after a friend's name: their game or connection is gone; they can rejoin at once.
- A Wi-Fi drop of up to ~30 s keeps you in the session.

## Single player
Run `gta_sa.exe` directly. Coop only loads when started through the launcher.

## Uninstall coop
`powershell -ExecutionPolicy Bypass -File coop-dev\testing\build.ps1 -Uninstall`
