# Changelog

## 1.0.1, 2026-10-27

Fixes from the first playtest of 1.0.0. Everyone needs 1.0.1 (the server turns away 1.0.0).

- **Anyone can start a mission.** Before, only the host's marker counted, and a friend walking into some contact markers (Smoke, Ryder, Cesar...) started the mission alone on their own game. Now a friend's marker asks the host's game, which moves the host into the marker and starts it for everyone.
- **Chat commands** (F6, `/help`): `/tp` and `/bring` players, `/goto`, `/pos`, `/mission <name or number>`, `/missions`, `/fail`, `/skip`, `/heal`, `/car`, `/gun`, `/time` and `/weather` (host). The `D1212` debug menu's mission list works for every player too.
- **One barber.** Players walking into a barber shop (or tattoo parlour, food place, clothes shop) close together each got a shopkeeper. Now everyone sees one.
- **Big Smoke and other mission characters** no longer attack the players when a friend hits them by accident. Your recruits don't either.
- **NPCs** no longer cower, sit or sink into the ground on one player's screen only.
- **Tag spraying** is shared reliably: each spray sends the exact tag it changed, paint never goes back down, and all 150 tags are synced (100 before).
- **Phone calls:** everyone hears the call and now also sees its subtitles.
- **Hospital and police station tips** after a respawn show only their text. Their camera scene locked players who respawned there together.

## 1.0.0, 2026-10-27

The first release of GTA Co-op, created and largely built by JessniX. It is built on CoopAndreas 0.3.0-alpha (upstream commit df03bbf). Changes from CoopAndreas:

- **Up to 4 players** (`maxplayers` in `server-config.ini`, default 4). No beta serial key: the launcher starts straight into co-op.
- **Every story mission can be played together.** Missions that CoopAndreas hasn't ported run on the host. Everyone else gets the objectives, markers, checkpoints, pickups, fires, trains, cutscenes, the MISSION PASSED/FAILED banner, the money reward and the wanted level.
- **Mission cars:** when the mission's characters fill the car, the others get a spare copy (green blip). Partners far from a starting mission are brought to the host.
- **Cutscenes:** skip vote (skips at N/N). Other players are hidden during scripted scenes. A cutscene left behind by a failed mission is cleared, and a stuck one is finished.
- **Shared saves:** whoever saves, everyone gets the host's progress and keeps their own look.
- **Shared world:** gang territories and recruits, oysters, horseshoes, snapshots and tags, trailers, the radio station in a shared car, and User Tracks songs (real audio files only).
- **Smoother play:** NPCs and other players' cars move smoothly instead of snapping. Walking shows as walking. Other players keep their own body after clothes changes.
- **Connections:** short drops of up to about 30 s don't disconnect you. A player whose game closed shows "(connection lost)" and can rejoin at once under the same name.
- **Playtest kit:** `/report <text>` in chat saves a report file. Crashes close the game quietly and write a crash log.
- **Crash fixes:** the startup crash with SilentPatch, the alt-tab freeze, the connect-menu port crash, the radar crash, vehicle pool corruption, the collision model and vehicle structure pools filling up, the mission death check, and crashes after a mission failed during a cutscene.
- **Lab:** `testing\` holds the automated test lab (hidden game copies, network simulator, mission sweeps, real playthroughs).

Details for each change: [MODLOG.md](MODLOG.md).
