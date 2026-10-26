# GTA San Andreas Co-op

**GTA Co-op 1.0.0:** play the whole GTA San Andreas story with friends. Up to 4 players share one world: missions, cutscenes, money, saves, gang territories and collectibles stay in sync. It runs on **GTA San Andreas PC 1.0 US** (Windows), online over the internet, a VPN or your LAN.

Created and largely built by **JessniX**, and maintained by **Multiplayer Everything** and **JessniX**. Based on [CoopAndreas](https://github.com/Tornamic/CoopAndreas) by Tornamic and its contributors (GPL-3.0).

## Install

1. You need your own **GTA San Andreas 1.0 US**. Steam and Rockstar Launcher copies must be downgraded to 1.0 first (search for "GTA SA downgrader"). The release contains no game files.
2. Download `GTACoop-1.0.0.zip` from [Releases](https://github.com/multiplayereverything/gta-coop/releases).
3. Copy everything in its `game` folder into your GTA San Andreas folder (next to `gta_sa.exe`) and run `install.bat` there once. `uninstall.bat` puts everything back.

Everyone needs the same version (1.0.0). The server turns away other versions.

## Play

- **Host:** run `server\server.exe` and leave it open (UDP port 6767, up to 4 players, see `server-config.ini`). Friends reach you through a port forward of UDP 6767, or through a VPN such as Tailscale, ZeroTier or Radmin VPN (easiest).
- **Everyone, the host too:** start `LaunchCoopAndreas.exe`, then Start Game, enter a nickname, the host's address (the host uses `127.0.0.1`) and port `6767`, and Connect.
- **The host joins first.** The first player in runs the story.

Full guide: [docs/HOW-TO-PLAY.md](docs/HOW-TO-PLAY.md).

## What's shared

- **Story missions:** objectives, markers, checkpoints, pickups, fires, trains, MISSION PASSED/FAILED, money rewards and the wanted level. Some missions are fully co-op. In the others the host drives the mission and everyone else follows it.
- **Cutscenes:** everyone watches; they skip when every player presses skip.
- **Mission cars:** when the mission's characters fill the car, the others get a spare copy of it (green blip).
- **Saves:** whoever saves, everyone gets the host's progress and keeps their own look.
- **The world:** gang territories and recruits, oysters, horseshoes, snapshots and tags, trailers, other players' cars and the radio (including User Tracks songs).

## If something goes wrong

- Type `/report what happened` in chat (F6). It saves a report file in `CoopAndreas_reports` in your GTA folder. Send it to us with the newest file in `CoopAndreas_crashes` if the game crashed.
- A friend whose game closed shows "(connection lost)" and can join again at once. Short Wi-Fi drops (up to about 30 s) don't throw anyone out.
- Report bugs in [Issues](https://github.com/multiplayereverything/gta-coop/issues).

## Tested

- Automated lab tests with hidden copies of the game on one PC: 101 of 102 story missions with 2 players, and 102 missions in one 4-player session with no crash.
- Real playthroughs with no shortcuts: Big Smoke, Ryder and Tagging Up Turf reached MISSION PASSED on both screens.
- Bad connections from good Wi-Fi to very bad, rejoining, collectibles, gang recruits, save sync and shared radio.

## Known issues

- A session between friends on separate PCs hasn't been tested by us yet.
- On the host's screen, joined players' bodies can look crumpled.
- Gang wars, buying property, stunt jumps and minigames (pool, basketball, dancing, casino) are each player's own.
- Race missions can't be passed by the lab bots; they are untested in co-op.
- CLEO+ breaks shooting sync (`install.bat` moves it out). Other mods may conflict; try without them first.
- Crash logs are also sent to the original CoopAndreas author's server, as in CoopAndreas. See [PRIVACY.md](PRIVACY.md).

## Build from source

Windows, Visual Studio 2022 and [xmake](https://xmake.io). Run `xmake` in the repo root (release, x86); the files land in `build\windows\x86\release`. `testing\build.ps1` builds and can install into a game folder. The original CoopAndreas build notes are in [docs/COOPANDREAS-README.md](docs/COOPANDREAS-README.md).

For contributors and agents: [AGENTS.md](AGENTS.md) (how the code and tests are laid out), [MODLOG.md](MODLOG.md) (what changed and why), [docs/MISSIONS.md](docs/MISSIONS.md) (mission status) and `testing\` (the lab scripts).

## License

GPL-3.0, like CoopAndreas. See [LICENSE](LICENSE). GTA San Andreas belongs to Rockstar Games; this project is not affiliated with them.
