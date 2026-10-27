#include "stdafx.h"
#include "CMissionStartSync.h"
#include "Debug/MissionRunner.h"
#include "CAutoTest.h"
#include <CPedPlacement.h>
#include <algorithm>
#include <cctype>
#include <deque>

static std::deque<Packets::Blips::MissionStartRequest> ms_requests;
static uint32_t ms_nScriptRequestAt = 0;  // a partner's contact script asked the host and set its own $onmission
static bool ms_bHostOnMission = false;

static std::string Lower(std::string s)
{
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
    return s;
}

bool CMissionStartSync::IsStoryMission(int id)
{
    return GetMissionName(id) != nullptr;
}

const char* CMissionStartSync::GetMissionName(int id)
{
    int count = 0;
    const MissionRunner::SMissionEntry* missions = MissionRunner::GetMissions(count);
    for (int i = 0; i < count; i++)
        if (missions[i].m_nId == id)
            return missions[i].m_szName;
    return nullptr;
}

int CMissionStartSync::FindMission(const std::string& text)
{
    std::string wanted = Lower(text);
    while (!wanted.empty() && wanted.back() == ' ')
        wanted.pop_back();
    while (!wanted.empty() && wanted.front() == ' ')
        wanted.erase(0, 1);
    if (wanted.empty())
        return -1;

    if (std::all_of(wanted.begin(), wanted.end(), [](char c) { return std::isdigit((unsigned char)c); }))
    {
        int id = std::atoi(wanted.c_str());
        return id >= 0 && id < CTheScripts::NumberOfMissionScripts ? id : -1;
    }

    int count = 0;
    const MissionRunner::SMissionEntry* missions = MissionRunner::GetMissions(count);
    for (int i = 0; i < count; i++)
        if (Lower(missions[i].m_szName) == wanted)
            return missions[i].m_nId;
    for (int i = 0; i < count; i++)
        if (Lower(missions[i].m_szName).find(wanted) != std::string::npos)
            return missions[i].m_nId;
    return -1;
}

static bool IsMissionScriptRunning()
{
    for (CRunningScript* s = CTheScripts::pActiveScripts; s; s = s->m_pNext)
        if (s->m_bIsMission && strncmp(s->m_szName, "coopand", 7) != 0)
            return true;
    return false;
}

bool CMissionStartSync::StartOnHost(int id, std::string& why)
{
    CPlayerPed* player = FindPlayerPed(0);
    if (!CLocalPlayer::m_bIsHost)
        why = "only the host's game can start missions";
    else if (!player || player->m_fHealth <= 0.0f || CWorld::Players[0].m_nPlayerState != PLAYERSTATE_PLAYING)
        why = "the host is wasted, busted or respawning";
    else if ((CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag]) ||
             IsMissionScriptRunning())
        // all missions share one code block: launching over a running mission (or a minigame) crashes the game
        why = "a mission is already running";
    else if (CCutsceneMgr::ms_running)
        why = "a cutscene is playing";
    else if (id < 0 || id >= CTheScripts::NumberOfMissionScripts)
        why = "no such mission";
    else
    {
        // what a mission trigger does before launching (scm/scripts/INT.txt, SMOKE.txt)
        if (CTheScripts::OnAMissionFlag)
            CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag] = 1;
        Command<Commands::LOAD_AND_LAUNCH_MISSION_INTERNAL>(id);
        CAutoTest::Event("mission_start_by_request", "\"id\":" + std::to_string(id));
        return true;
    }
    return false;
}

void CMissionStartSync::MoveLocalPlayer(const CVector& position, uint8_t area, bool exact)
{
    CPlayerPed* player = FindPlayerPed(0);
    if (!player)
        return;

    CVector target = position;
    if (!exact)
    {
        // beside the other player, not inside them
        target.x += 1.2f;
        if (area == 0 && !CPedPlacement::FindZCoorForPed(&target))
            target = position;
    }

    bool inVehicle = player->m_nPedFlags.bInVehicle && player->m_pVehicle;
    bool changingArea = player->m_nAreaCode != area || CGame::currArea != area;
    int ref = CPools::GetPedRef(player);

    if (changingArea)
    {
        Command<Commands::SET_AREA_VISIBLE>((int)area);
        Command<Commands::SET_CHAR_AREA_VISIBLE>(ref, (int)area);
    }
    Command<Commands::LOAD_SCENE>(target.x, target.y, target.z);

    // a car can't go through a door: leave it behind when the target is in another area or inside
    if (inVehicle && (changingArea || area != 0 || exact))
        Command<Commands::WARP_CHAR_FROM_CAR_TO_COORD>(ref, target.x, target.y, target.z);
    else if (inVehicle)
        player->m_pVehicle->Teleport(target, false);
    else
        player->Teleport(target, false);
}

void CMissionStartSync::Request(int id)
{
    const char* name = GetMissionName(id);
    std::string label = name ? name : "mission " + std::to_string(id);

    if (CLocalPlayer::m_bIsHost)
    {
        std::string why;
        if (StartOnHost(id, why))
            CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}Starting %s.", label.c_str());
        else
            CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}Can't start %s: %s.", label.c_str(), why.c_str());
        return;
    }

    Packets::Blips::MissionStartRequest packet{};
    packet.missionId = (int16_t)id;
    packet.atMarker = false;
    GetPacketFactory().Send(packet);
    CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}Asked the host's game to start %s.", label.c_str());
}

bool CMissionStartSync::InterceptScriptLaunch(CRunningScript* script, int id)
{
    if (CLocalPlayer::m_bIsHost || !CNetwork::m_bAuthenticated || script->m_bIsMission || !IsStoryMission(id))
        return false;

    CPlayerPed* player = FindPlayerPed(0);
    if (!player)
        return false;

    Packets::Blips::MissionStartRequest packet{};
    packet.missionId = (int16_t)id;
    packet.atMarker = true;
    packet.position = player->GetPosition();
    packet.area = player->m_nAreaCode;
    GetPacketFactory().Send(packet);

    ms_nScriptRequestAt = GetTickCount();
    CAutoTest::Event("mission_start_requested", "\"id\":" + std::to_string(id) + ",\"script\":\"" +
                                                    std::string(script->m_szName, strnlen(script->m_szName, 8)) + "\"");
    return true;
}

void CMissionStartSync::HandleRequest(const Packets::Blips::MissionStartRequest& packet)
{
    if (CLocalPlayer::m_bIsHost && ms_requests.size() < 8)
        ms_requests.push_back(packet);
}

void CMissionStartSync::OnHostMissionFlag(bool onMission)
{
    ms_bHostOnMission = onMission;
    if (onMission)
        ms_nScriptRequestAt = 0;
}

void CMissionStartSync::Process()
{
    // partner: the contact script set $onmission = 1 before its launch became a request. The host started nothing
    // (busy, in a cutscene, on another mission): free the trigger again, or this player's markers stay dead
    if (ms_nScriptRequestAt && GetTickCount() - ms_nScriptRequestAt > 8000)
    {
        ms_nScriptRequestAt = 0;
        if (!CLocalPlayer::m_bIsHost && !ms_bHostOnMission && CTheScripts::OnAMissionFlag &&
            CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag] && !IsMissionScriptRunning())
        {
            CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag] = 0;
            CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}The host's game couldn't start the mission right now. Try again "
                              "in a moment.");
        }
    }

    if (!CLocalPlayer::m_bIsHost)
    {
        ms_requests.clear();
        return;
    }

    while (!ms_requests.empty())
    {
        Packets::Blips::MissionStartRequest packet = ms_requests.front();
        ms_requests.pop_front();

        CNetworkPlayer* requester = CNetworkPlayerManager::GetPlayer(packet.senderPlayerid);
        std::string who = requester ? requester->GetName() : "A player";
        const char* name = GetMissionName(packet.missionId);
        std::string label = name ? name : "mission " + std::to_string(packet.missionId);

        std::string why;
        CPlayerPed* host = FindPlayerPed(0);
        bool canStart = host && host->m_fHealth > 0.0f && CWorld::Players[0].m_nPlayerState == PLAYERSTATE_PLAYING &&
                        !(CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag]) &&
                        !IsMissionScriptRunning() && !CCutsceneMgr::ms_running;

        // the mission runs on the host's game at the host's position: put the host where the partner stood
        if (canStart && packet.atMarker && (host->GetPosition() - packet.position).Magnitude() > 3.0f)
            MoveLocalPlayer(packet.position, packet.area, true);

        if (StartOnHost(packet.missionId, why))
        {
            CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}%s started %s.", who.c_str(), label.c_str());
        }
        else
        {
            CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}%s wanted to start %s, but %s.", who.c_str(), label.c_str(),
                              why.c_str());
            // tell everyone (the requester only sees chat); sent as the host's chat line
            Packets::System::ChatMessage chat{};
            std::string text = "[auto] Can't start " + label + ": " + why;
            std::wstring wtext(text.begin(), text.end());
            wcsncpy_s(chat.message, wtext.c_str(), _TRUNCATE);
            GetPacketFactory().Send(chat);
        }
    }
}
