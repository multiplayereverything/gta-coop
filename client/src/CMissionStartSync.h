#pragma once

#include "network/packets/blips.h"

// Every player can start story missions; the host's game always runs them (all mission sync is built on that).
// - a partner whose contact script reaches a mission launch (SMOKE, RYDER, CESAR... markers check the local player)
//   no longer starts the mission alone on its own game: the launch becomes a request to the host, which moves the
//   host into the marker and launches it there; the usual mission-start teleport then brings everyone along
// - the all-players markers (Coop.LocateAllPlayersOnFoot3D: INT, SWEET) also fire on the host when a partner stands in
//   them (CCommandLocateAllPlayersOnFoot3D)
// - chat /mission and the D1212 debug menu ask the same way
class CMissionStartSync
{
public:
    // story mission ids/names (Debug/MissionRunner.cpp)
    static bool IsStoryMission(int id);
    static const char* GetMissionName(int id);
    // "11", "big smoke", "smoke" -> id, or -1
    static int FindMission(const std::string& text);

    // host: launch now; anyone else: ask the host
    static void Request(int id);
    // a script on this (non-host) game is about to run LOAD_AND_LAUNCH_MISSION_INTERNAL: true = handled here (the
    // script's own launch is skipped)
    static bool InterceptScriptLaunch(CRunningScript* script, int id);

    static void HandleRequest(const Packets::Blips::MissionStartRequest& packet);
    static void OnHostMissionFlag(bool onMission);
    static void Process();

    // host: launches `id` if nothing is in the way; `why` says what was
    static bool StartOnHost(int id, std::string& why);
    // moves the local player (and the car they drive) next to `position` in `area`
    static void MoveLocalPlayer(const CVector& position, uint8_t area, bool exact);
};
