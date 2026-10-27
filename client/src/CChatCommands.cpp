#include "stdafx.h"
#include "CChatCommands.h"
#include "CMissionStartSync.h"
#include "CCutsceneSkipVote.h"
#include "Debug/MissionRunner.h"
#include <CModelInfo.h>
#include <CWeaponInfo.h>
#include <CStreaming.h>
#include <deque>
#include <sstream>
#include <algorithm>
#include <cctype>

static std::deque<std::string> ms_pending;
static std::deque<Packets::Blips::TeleportPlayerRequest> ms_teleports;

#define COOP_MSG "{c7a6ff}[Coop] {d6dce8}"

static std::string Narrow(const std::wstring& w)
{
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), s.data(), n, nullptr, nullptr);
    return s;
}

static std::string Lower(std::string s)
{
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)std::tolower(c); });
    return s;
}

static const char* COMMANDS[] = {"help", "players", "tp", "bring", "goto", "pos", "mission", "missions", "fail",
                                 "skip", "heal", "car", "gun", "time", "weather"};

bool CChatCommands::Handle(const std::wstring& line)
{
    if (line.empty() || line[0] != L'/')
        return false;
    std::string text = Narrow(line.substr(1));
    std::string verb = Lower(text.substr(0, text.find(' ')));
    if (std::find_if(std::begin(COMMANDS), std::end(COMMANDS), [&](const char* c) { return verb == c; }) ==
        std::end(COMMANDS))
        return false;  // "/something else": an ordinary chat line, as before
    if (ms_pending.size() < 16)
        ms_pending.push_back(text);
    return true;
}

// "2" (player id), "jess" (start of a name) -> that player
static CNetworkPlayer* FindPlayer(const std::string& what)
{
    if (what.empty())
        return nullptr;
    if (std::all_of(what.begin(), what.end(), [](char c) { return std::isdigit((unsigned char)c); }))
        for (CNetworkPlayer* p : CNetworkPlayerManager::m_pPlayers)
            if (p->m_playerId.value() == (uint32_t)std::atoi(what.c_str()))
                return p;
    std::string wanted = Lower(what);
    for (CNetworkPlayer* p : CNetworkPlayerManager::m_pPlayers)
        if (Lower(p->GetName()) == wanted)
            return p;
    for (CNetworkPlayer* p : CNetworkPlayerManager::m_pPlayers)
        if (Lower(p->GetName()).rfind(wanted, 0) == 0)
            return p;
    return nullptr;
}

static uint8_t AreaOf(CPed* ped)
{
    // interiors sit ~1000 m up in their own area
    return ped->GetPosition().z > 500.0f ? ped->m_nAreaCode : 0;
}

static bool LocalPlayerCanMove(CPlayerPed* me)
{
    if (!me || me->m_fHealth <= 0.0f || CWorld::Players[0].m_nPlayerState != PLAYERSTATE_PLAYING)
    {
        CChat::AddMessage(COOP_MSG "Not while wasted, busted or respawning.");
        return false;
    }
    if (CCutsceneMgr::ms_running)
    {
        CChat::AddMessage(COOP_MSG "Not during a cutscene.");
        return false;
    }
    return true;
}

static void Run(const std::string& text)
{
    std::istringstream in(text);
    std::string verb;
    in >> verb;
    verb = Lower(verb);
    std::string rest;
    std::getline(in, rest);
    while (!rest.empty() && rest.front() == ' ')
        rest.erase(0, 1);
    std::istringstream args(rest);
    CPlayerPed* me = FindPlayerPed(0);

    if (verb == "help")
    {
        CChat::AddMessage(COOP_MSG "/players, /tp <player>, /bring <player>, /goto <x> <y> <z>, /pos");
        CChat::AddMessage(COOP_MSG "/mission <name or number>, /missions [page], /fail, /skip");
        CChat::AddMessage(COOP_MSG "/heal, /car <name or id>, /gun <weapon id> [ammo], /time <hour> [min], "
                                   "/weather <id>, /report <what happened>");
    }
    else if (verb == "players")
    {
        CChat::AddMessage(COOP_MSG "You: %s%s", CLocalPlayer::m_Name, CLocalPlayer::m_bIsHost ? " (host)" : "");
        for (CNetworkPlayer* p : CNetworkPlayerManager::m_pPlayers)
            CChat::AddMessage(COOP_MSG "%u: %s%s%s", p->m_playerId.value(), p->GetName().c_str(),
                              p->m_bIsHost ? " (host)" : "", p->m_bConnectionLost ? " (connection lost)" : "");
    }
    else if (verb == "tp")
    {
        CNetworkPlayer* target = FindPlayer(rest);
        if (!target || !target->m_pPed || !target->m_pPed->m_matrix)
            CChat::AddMessage(COOP_MSG "No player \"%s\". /players lists them.", rest.c_str());
        else if (LocalPlayerCanMove(me))
        {
            CMissionStartSync::MoveLocalPlayer(target->m_pPed->GetPosition(), AreaOf(target->m_pPed), false);
            CChat::AddMessage(COOP_MSG "Teleported to %s.", target->GetName().c_str());
        }
    }
    else if (verb == "bring")
    {
        CNetworkPlayer* target = FindPlayer(rest);
        if (!target)
            CChat::AddMessage(COOP_MSG "No player \"%s\". /players lists them.", rest.c_str());
        else if (me)
        {
            Packets::Blips::TeleportPlayerRequest packet{};
            packet.target = target->m_playerId;
            packet.position = me->GetPosition();
            packet.area = AreaOf(me);
            GetPacketFactory().Send(packet);
            CChat::AddMessage(COOP_MSG "Bringing %s to you.", target->GetName().c_str());
        }
    }
    else if (verb == "goto")
    {
        float x, y, z;
        if (!(args >> x >> y >> z))
            CChat::AddMessage(COOP_MSG "Usage: /goto <x> <y> <z>");
        else if (LocalPlayerCanMove(me))
            CMissionStartSync::MoveLocalPlayer(CVector(x, y, z), z > 500.0f ? me->m_nAreaCode : 0, true);
    }
    else if (verb == "pos")
    {
        if (me)
            CChat::AddMessage(COOP_MSG "%.1f %.1f %.1f, interior %d, heading %.0f", me->GetPosition().x,
                              me->GetPosition().y, me->GetPosition().z, (int)me->m_nAreaCode,
                              me->m_fCurrentRotation * 57.2958f);
    }
    else if (verb == "mission")
    {
        int id = CMissionStartSync::FindMission(rest);
        if (id < 0)
            CChat::AddMessage(COOP_MSG "No mission \"%s\". /missions lists them.", rest.c_str());
        else
            CMissionStartSync::Request(id);
    }
    else if (verb == "missions")
    {
        int page = 1;
        args >> page;
        int count = 0;
        const MissionRunner::SMissionEntry* missions = MissionRunner::GetMissions(count);
        const int perPage = 12;
        int pages = (count + perPage - 1) / perPage;
        page = (std::clamp)(page, 1, pages);
        std::string line;
        for (int i = (page - 1) * perPage; i < (std::min)(count, page * perPage); i++)
        {
            line += std::to_string(missions[i].m_nId) + " " + missions[i].m_szName + ", ";
            if (line.size() > 70)
            {
                CChat::AddMessage(COOP_MSG "%s", line.c_str());
                line.clear();
            }
        }
        if (!line.empty())
            CChat::AddMessage(COOP_MSG "%s", line.c_str());
        CChat::AddMessage(COOP_MSG "Page %d of %d (/missions <page>). Start one: /mission <name or number>", page,
                          pages);
    }
    else if (verb == "fail")
    {
        bool running = false;
        for (CRunningScript* s = CTheScripts::pActiveScripts; s; s = s->m_pNext)
            running |= s->m_bIsMission && strncmp(s->m_szName, "coopand", 7) != 0;
        if (!CLocalPlayer::m_bIsHost)
            CChat::AddMessage(COOP_MSG "Only the host's game can fail the mission.");
        else if (!running)
            CChat::AddMessage(COOP_MSG "No mission is running.");
        else
            Command<Commands::FAIL_CURRENT_MISSION>();
    }
    else if (verb == "skip")
    {
        if (CCutsceneMgr::ms_running)
            CCutsceneSkipVote::PressSkip();
        else
            CChat::AddMessage(COOP_MSG "No cutscene is playing.");
    }
    else if (verb == "heal")
    {
        if (me && me->m_fHealth > 0.0f && CWorld::Players[0].m_nPlayerState == PLAYERSTATE_PLAYING)
        {
            me->m_fHealth = me->m_fMaxHealth;
            me->m_fArmour = 100.0f;
        }
    }
    else if (verb == "car")
    {
        int model = -1;
        if (!rest.empty() && std::isdigit((unsigned char)rest[0]))
            model = std::atoi(rest.c_str());
        else if (!rest.empty())
        {
            std::string name = rest;
            CModelInfo::GetModelInfo(name.data(), &model);
        }
        if (model < 400 || model > 611 || !CModelInfo::IsVehicleModelType(model) || model == 537 || model == 538 ||
            model == 569 || model == 570 || model == 590 || model == 449)
            CChat::AddMessage(COOP_MSG "Not a vehicle: \"%s\" (a name like infernus, or 400-611; no trains).",
                              rest.c_str());
        else if (LocalPlayerCanMove(me))
        {
            if (me->m_nPedFlags.bInVehicle)
                CChat::AddMessage(COOP_MSG "Get out of your vehicle first.");
            else if (CVehicle* vehicle = CCheat::VehicleCheat(model))
            {
                vehicle->m_nVehicleFlags.bHasBeenOwnedByPlayer = true;
                Command<Commands::WARP_CHAR_INTO_CAR>(CPools::GetPedRef(me), CPools::GetVehicleRef(vehicle));
            }
        }
    }
    else if (verb == "gun")
    {
        int weapon = 0, ammo = 500;
        args >> weapon >> ammo;
        CWeaponInfo* info = weapon >= 1 && weapon <= 46 ? CWeaponInfo::GetWeaponInfo((eWeaponType)weapon, 1) : nullptr;
        if (!info)
            CChat::AddMessage(COOP_MSG "Usage: /gun <weapon id 1-46> [ammo], e.g. 24 deagle, 31 m4, 29 mp5");
        else if (me)
        {
            if (info->m_nModelId1 > 0)
            {
                CStreaming::RequestModel(info->m_nModelId1, 2);
                CStreaming::LoadAllRequestedModels(false);
            }
            me->GiveWeapon((eWeaponType)weapon, (unsigned)(std::max)(ammo, 1), true);
            me->SetCurrentWeapon((eWeaponType)weapon);
        }
    }
    else if (verb == "time")
    {
        int hour = -1, minute = 0;
        args >> hour >> minute;
        if (!CLocalPlayer::m_bIsHost)
            CChat::AddMessage(COOP_MSG "Only the host can set the time (everyone follows the host's clock).");
        else if (hour < 0 || hour > 23 || minute < 0 || minute > 59)
            CChat::AddMessage(COOP_MSG "Usage: /time <hour 0-23> [minute]");
        else
            CClock::SetGameClock((unsigned char)hour, (unsigned char)minute, CClock::CurrentDay);
    }
    else if (verb == "weather")
    {
        int weather = -1;
        args >> weather;
        if (!CLocalPlayer::m_bIsHost)
            CChat::AddMessage(COOP_MSG "Only the host can set the weather (everyone follows the host's).");
        else if (weather < 0 || weather > 22)
            CChat::AddMessage(COOP_MSG "Usage: /weather <0-22> (0 sunny, 8 rain, 9 fog, 16 storm, 19 sandstorm)");
        else
            CWeather::ForceWeatherNow((short)weather);
    }
}

void CChatCommands::Process()
{
    while (!ms_pending.empty())
    {
        std::string text = ms_pending.front();
        ms_pending.pop_front();
        Run(text);
    }

    while (!ms_teleports.empty())
    {
        Packets::Blips::TeleportPlayerRequest packet = ms_teleports.front();
        ms_teleports.pop_front();
        CNetworkPlayer* from = CNetworkPlayerManager::GetPlayer(packet.senderPlayerid);
        std::string who = from ? from->GetName() : "A player";
        CPlayerPed* me = FindPlayerPed(0);
        if (!me || me->m_fHealth <= 0.0f || CWorld::Players[0].m_nPlayerState != PLAYERSTATE_PLAYING ||
            CCutsceneMgr::ms_running)
            continue;
        CMissionStartSync::MoveLocalPlayer(packet.position, packet.area, false);
        CChat::AddMessage(COOP_MSG "%s brought you to them.", who.c_str());
    }
}

void CChatCommands::HandleTeleportRequest(const Packets::Blips::TeleportPlayerRequest& packet)
{
    if (ms_teleports.size() < 4)
        ms_teleports.push_back(packet);
}
