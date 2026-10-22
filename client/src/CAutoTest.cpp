#include "stdafx.h"
#include "CAutoTest.h"
#include "CCutsceneSkipVote.h"
#include <CMessages.h>
#include <deque>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace fs = std::filesystem;

static fs::path ms_dir;
static char ms_ip[129] = "127.0.0.1";
static unsigned short ms_port = Config::DEFAULT_PORT;
static char ms_name[Config::MAX_NICKNAME_LENGTH + 1] = "Tester";

static bool ms_bGameStartRequested = false;
static uint32_t ms_nMenuFrames = 0;
static uint32_t ms_nLastStatusWrite = 0;
static uint32_t ms_nFrames = 0;  // game frames since the last status write, for a measured fps
static size_t ms_nCommandsDone = 0;
static std::deque<std::string> ms_chatLog;
static std::deque<std::string> ms_commandLog;

static const char* GetArg(const char* cmd, const char* key)
{
    const char* found = strstr(cmd, key);
    if (!found)
        return nullptr;
    found += strlen(key);
    while (*found == ' ')
        found++;
    return found;
}

static void CopyArg(const char* value, char* out, size_t size)
{
    size_t n = 0;
    while (value[n] && value[n] != ' ' && n + 1 < size)
    {
        out[n] = value[n];
        n++;
    }
    out[n] = '\0';
}

static std::string JsonEscape(const std::string& s)
{
    std::string out;
    for (char c : s)
    {
        if (c == '"' || c == '\\')
            out += '\\';
        if ((unsigned char)c < 0x20)
            continue;
        out += c;
    }
    return out;
}

void CAutoTest::Init()
{
    const char* cmd = GetCommandLineA();
    if (!strstr(cmd, "--autotest"))
        return;

    ms_bEnabled = true;

    if (const char* v = GetArg(cmd, "-autoip"))
        CopyArg(v, ms_ip, sizeof(ms_ip));
    if (const char* v = GetArg(cmd, "-autoport"))
        ms_port = (unsigned short)atoi(v);
    if (const char* v = GetArg(cmd, "-autoname"))
        CopyArg(v, ms_name, sizeof(ms_name));

    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, MAX_PATH);
    ms_dir = fs::path(exePath).parent_path() / "CoopAndreas" / "autotest";
    // -autodir <sub>: separate files per instance when several games run from one folder
    if (const char* v = GetArg(cmd, "-autodir"))
    {
        char sub[64];
        CopyArg(v, sub, sizeof(sub));
        ms_dir /= sub;
    }
    std::error_code ec;
    fs::create_directories(ms_dir, ec);

    Event("boot", "\"ip\":\"" + JsonEscape(ms_ip) + "\",\"port\":" + std::to_string(ms_port) + ",\"name\":\"" +
                      JsonEscape(ms_name) + "\",\"version\":\"" COOPANDREAS_VERSION "\"");
}

void CAutoTest::Event(const char* type, const std::string& fields)
{
    if (!ms_bEnabled)
        return;

    std::ofstream f(ms_dir / "events.jsonl", std::ios::app);
    f << "{\"t\":" << GetTickCount() << ",\"ev\":\"" << type << "\"" << (fields.empty() ? "" : ",") << fields << "}\n";
}

static std::string Vec(const CVector& v)
{
    char buf[96];
    snprintf(buf, sizeof(buf), "\"x\":%.1f,\"y\":%.1f,\"z\":%.1f", v.x, v.y, v.z);
    return buf;
}

// the running mission script on the host (non-hosts only get the on-mission flag)
static std::string GetMissionScriptName()
{
    for (CRunningScript* s = CTheScripts::pActiveScripts; s; s = s->m_pNext)
    {
        if (s->m_bIsMission && strncmp(s->m_szName, "coopand", 7) != 0)
        {
            char name[9]{};
            memcpy(name, s->m_szName, 8);
            return name;
        }
    }
    return "";
}

// which of the mission result big messages is on screen right now ("" if none)
static std::string GetMissionResultMessage()
{
    static const char* keys[] = {"M_PASS", "M_PASSR", "M_PASSD", "M_PASSS", "M_FAIL"};
    for (int style = 0; style < 7; style++)
    {
        char* text = CMessages::BIGMessages[style].m_Current.m_pText;
        if (!text)
            continue;
        for (const char* key : keys)
        {
            if (text == TheText.Get(key))
                return key;
        }
    }
    return "";
}

void CAutoTest::DetectMission()
{
    static bool onMission = false, cutscene = false;
    static int votes = -1, voters = -1;
    static std::string result;

    bool nowOnMission = CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
    if (nowOnMission != onMission)
    {
        onMission = nowOnMission;
        if (onMission)
            Event("mission_started", "\"script\":\"" + JsonEscape(GetMissionScriptName()) + "\",\"host\":" +
                                         (CLocalPlayer::m_bIsHost ? "true" : "false"));
        else
            Event("mission_ended");
    }

    std::string nowResult = GetMissionResultMessage();
    if (nowResult != result)
    {
        result = nowResult;
        if (!result.empty())
            Event(result == "M_FAIL" ? "mission_failed" : "mission_passed", "\"gxt\":\"" + result + "\"");
    }

    if (CCutsceneMgr::ms_running != cutscene)
    {
        cutscene = CCutsceneMgr::ms_running;
        if (cutscene)
            Event("cutscene_started", "\"name\":\"" + JsonEscape(std::string(CCutsceneMgr::ms_cutsceneName, 0, 8)) + "\"");
        else
            Event("cutscene_ended", std::string("\"skipped\":") + (CCutsceneMgr::ms_wasCutsceneSkipped ? "true" : "false"));
    }

    if (CCutsceneSkipVote::GetVotes() != votes || CCutsceneSkipVote::GetVoters() != voters)
    {
        votes = CCutsceneSkipVote::GetVotes();
        voters = CCutsceneSkipVote::GetVoters();
        if (voters > 0)
            Event("skip_vote_state", "\"votes\":" + std::to_string(votes) + ",\"voters\":" + std::to_string(voters) +
                                         ",\"voted\":" + (CCutsceneSkipVote::HasVoted() ? "true" : "false"));
    }
}

void CAutoTest::DetectChanges()
{
    static bool connected = false, authenticated = false, isHost = false, inVehicle = false, dead = false;
    static int interior = -1;
    static std::unordered_map<uint32_t, bool> players;  // id -> has ped

    if (CNetwork::m_bConnected != connected)
    {
        connected = CNetwork::m_bConnected;
        Event(connected ? "connected" : "disconnected");
    }
    if (CNetwork::m_bAuthenticated != authenticated)
    {
        authenticated = CNetwork::m_bAuthenticated;
        if (authenticated)
            Event("authenticated", "\"id\":" + std::to_string(CNetworkPlayerManager::m_localPlayerId.value()));
    }
    if (CLocalPlayer::m_bIsHost != isHost)
    {
        isHost = CLocalPlayer::m_bIsHost;
        Event(isHost ? "host_gained" : "host_lost");
    }

    std::unordered_map<uint32_t, bool> now;
    for (CNetworkPlayer* np : CNetworkPlayerManager::m_pPlayers)
    {
        uint32_t id = np->m_playerId.value();
        bool hasPed = np->m_pPed != nullptr;
        now[id] = hasPed;

        auto it = players.find(id);
        std::string who = "\"id\":" + std::to_string(id) + ",\"name\":\"" + JsonEscape(np->m_Name) + "\"";
        if (it == players.end())
            Event("player_joined", who);
        if (hasPed && (it == players.end() || !it->second))
            Event("player_ped_created", who + "," + Vec(np->m_pPed->GetPosition()));
    }
    for (auto& [id, hadPed] : players)
    {
        if (now.find(id) == now.end())
            Event("player_left", "\"id\":" + std::to_string(id));
    }
    players = std::move(now);

    CPlayerPed* player = FindPlayerPed(0);
    if (!player || !player->m_matrix)
        return;

    bool nowInVehicle = player->m_nPedFlags.bInVehicle && player->m_pVehicle;
    if (nowInVehicle != inVehicle)
    {
        inVehicle = nowInVehicle;
        if (inVehicle)
            Event("vehicle_entered", "\"model\":" + std::to_string(player->m_pVehicle->m_nModelIndex));
        else
            Event("vehicle_exited");
    }
    if ((int)player->m_nAreaCode != interior)
    {
        interior = player->m_nAreaCode;
        Event("interior", "\"area\":" + std::to_string(interior) + "," + Vec(player->GetPosition()));
    }
    bool nowDead = player->m_fHealth <= 0.0f;
    if (nowDead != dead)
    {
        dead = nowDead;
        Event(dead ? "wasted" : "alive", Vec(player->GetPosition()));
    }
}

void CAutoTest::ProcessMenu(CMenuManager* pMenu)
{
    if (!ms_bEnabled)
        return;

    DetectChanges();
    WriteStatus(false);

    // the new game has loaded but the frontend stays up as the pause menu, and nothing
    // (including the network handshake) is processed while paused: press "Resume"
    if (ms_bGameStartRequested && !pMenu->m_bGameNotLoaded && pMenu->m_bMenuActive)
    {
        // same as clicking RESUME; retry slowly in case the frontend ignores it while still loading
        if (++ms_nMenuFrames > 30 && !pMenu->m_bShutDownFrontEndRequested)
        {
            ms_nMenuFrames = 0;
            ms_commandLog.push_back("menu: resume");
            Event("menu_resume");
            pMenu->RequestFrontEndShutDown();
        }
        return;
    }

    // let the frontend settle for a moment, then behave like "Start Game -> Connect -> New Game"
    if (ms_bGameStartRequested || !pMenu->m_bGameNotLoaded || ++ms_nMenuFrames < 60)
        return;
    ms_nMenuFrames = 0;

    ms_bGameStartRequested = true;

    // config was already loaded from the ini, override it with the test values
    strcpy_s(CLocalPlayer::m_Name, ms_name);
    strcpy_s(CNetwork::m_IpAddress, ms_ip);
    CNetwork::m_nPort = ms_port;

    ms_commandLog.push_back("menu: starting new game");
    Event("menu_new_game");
    pMenu->DoSettingsBeforeStartingAGame();
}

void CAutoTest::ProcessGame()
{
    if (!ms_bEnabled)
        return;

    static bool firstFrame = true;
    if (firstFrame)
    {
        firstFrame = false;
        Event("game_loop_running");
    }

    ms_nFrames++;
    DetectChanges();
    DetectMission();
    ExecuteCommands();
    WriteStatus(true);
}

void CAutoTest::OnChatMessage(const char* name, const wchar_t* message)
{
    if (!ms_bEnabled)
        return;

    char text[Config::MAX_CHAT_MESSAGE_LENGTH * 3 + 1];
    WideCharToMultiByte(CP_UTF8, 0, message, -1, text, sizeof(text), nullptr, nullptr);
    ms_chatLog.push_back(std::string(name) + ": " + text);
    Event("chat_received", "\"from\":\"" + JsonEscape(name) + "\",\"text\":\"" + JsonEscape(text) + "\"");
    if (ms_chatLog.size() > 20)
        ms_chatLog.pop_front();
}

void CAutoTest::WriteStatus(bool inGame)
{
    uint32_t now = GetTickCount();
    uint32_t elapsed = now - ms_nLastStatusWrite;
    if (elapsed < 500)
        return;
    float fps = (inGame && ms_nLastStatusWrite != 0) ? ms_nFrames * 1000.0f / elapsed : 0.0f;
    ms_nFrames = 0;
    ms_nLastStatusWrite = now;

    std::ostringstream js;
    js.setf(std::ios::fixed);
    js.precision(2);

    js << "{\"tick\":" << now << ",\"state\":\"" << (inGame ? "ingame" : "menu") << "\""
       << ",\"connected\":" << (CNetwork::m_bConnected ? "true" : "false")
       << ",\"authenticated\":" << (CNetwork::m_bAuthenticated ? "true" : "false")
       << ",\"id\":" << CNetworkPlayerManager::m_localPlayerId.value()
       << ",\"isHost\":" << (CLocalPlayer::m_bIsHost ? "true" : "false")
       << ",\"name\":\"" << JsonEscape(CLocalPlayer::m_Name) << "\""
       << ",\"rtt\":" << CNetwork::GetRTT() << ",\"fps\":" << fps << ",\"focused\":" << (GetForegroundWindow() == *(HWND*)0xC97C1C ? "true" : "false");  // 0xC97C1C: game window

    if (inGame)
    {
        js << ",\"onMission\":"
           << ((CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag]) ? "true" : "false")
           << ",\"mission\":\"" << JsonEscape(GetMissionScriptName()) << "\""
           << ",\"cutscene\":\"" << (CCutsceneMgr::ms_running ? JsonEscape(std::string(CCutsceneMgr::ms_cutsceneName, 0, 8)) : "")
           << "\",\"skipVotes\":" << CCutsceneSkipVote::GetVotes() << ",\"skipVoters\":" << CCutsceneSkipVote::GetVoters();
    }

    CPlayerPed* player = inGame ? FindPlayerPed(0) : nullptr;
    if (player && player->m_matrix)
    {
        CVector& p = player->m_matrix->pos;
        bool inVehicle = player->m_nPedFlags.bInVehicle && player->m_pVehicle;
        js << ",\"local\":{\"x\":" << p.x << ",\"y\":" << p.y << ",\"z\":" << p.z
           << ",\"health\":" << player->m_fHealth << ",\"inVehicle\":" << (inVehicle ? "true" : "false")
           << ",\"vehicleModel\":" << (inVehicle ? player->m_pVehicle->m_nModelIndex : 0)
           << ",\"interior\":" << (int)player->m_nAreaCode << "}";
    }

    js << ",\"players\":[";
    bool first = true;
    for (CNetworkPlayer* np : CNetworkPlayerManager::m_pPlayers)
    {
        js << (first ? "" : ",") << "{\"id\":" << np->m_playerId.value() << ",\"name\":\"" << JsonEscape(np->m_Name)
           << "\",\"hasPed\":" << (np->m_pPed ? "true" : "false") << ",\"isHost\":" << (np->m_bIsHost ? "true" : "false");
        if (np->m_pPed && np->m_pPed->m_matrix)
        {
            CVector& p = np->m_pPed->m_matrix->pos;
            js << ",\"x\":" << p.x << ",\"y\":" << p.y << ",\"z\":" << p.z;
            if (player && player->m_matrix)
                js << ",\"distance\":" << (p - player->m_matrix->pos).Magnitude();
            js << ",\"inVehicle\":" << (np->m_pPed->m_nPedFlags.bInVehicle ? "true" : "false");
        }
        js << "}";
        first = false;
    }
    js << "]";

    js << ",\"networkVehicles\":" << CNetworkVehicleManager::m_pVehicles.size()
       << ",\"networkPeds\":" << CNetworkPedManager::m_pPeds.size();

    js << ",\"chat\":[";
    first = true;
    for (const std::string& line : ms_chatLog)
    {
        js << (first ? "" : ",") << "\"" << JsonEscape(line) << "\"";
        first = false;
    }
    js << "],\"commands\":[";
    first = true;
    for (const std::string& line : ms_commandLog)
    {
        js << (first ? "" : ",") << "\"" << JsonEscape(line) << "\"";
        first = false;
    }
    js << "]}";

    // write then rename, so the test script never reads half a file
    fs::path tmp = ms_dir / "status.tmp";
    {
        std::ofstream f(tmp, std::ios::trunc);
        f << js.str();
    }
    MoveFileExA(tmp.string().c_str(), (ms_dir / "status.json").string().c_str(), MOVEFILE_REPLACE_EXISTING);
}

void CAutoTest::ExecuteCommands()
{
    // poll at 10 Hz and share the file, so the test script can append while we read
    static uint32_t lastPoll = 0;
    uint32_t now = GetTickCount();
    if (now - lastPoll < 100)
        return;
    lastPoll = now;

    std::ifstream f(ms_dir / "commands.txt", std::ios::in, _SH_DENYNO);
    if (!f)
        return;

    std::string line;
    size_t index = 0;
    while (std::getline(f, line))
    {
        if (index++ < ms_nCommandsDone)
            continue;
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        if (!line.empty())
            Execute(line);
        ms_nCommandsDone = index;
    }
}

void CAutoTest::Execute(const std::string& line)
{
    std::istringstream in(line);
    std::string verb;
    in >> verb;

    CPlayerPed* player = FindPlayerPed(0);
    std::string result = "ok";

    if (verb == "chat")
    {
        std::string text;
        std::getline(in, text);
        if (!text.empty() && text[0] == ' ')
            text.erase(0, 1);

        Packets::System::ChatMessage packet{};
        MultiByteToWideChar(CP_UTF8, 0, text.c_str(), -1, packet.message, Config::MAX_CHAT_MESSAGE_LENGTH);
        packet.message[Config::MAX_CHAT_MESSAGE_LENGTH] = L'\0';
        CChat::AddPlayerChatMessage(CLocalPlayer::m_Name, packet.message);
        GetPacketFactory().Send(packet);
    }
    else if (verb == "teleport")
    {
        float x = 0, y = 0, z = 0;
        in >> x >> y >> z;
        if (player->m_nPedFlags.bInVehicle && player->m_pVehicle)
            player->m_pVehicle->Teleport(CVector(x, y, z), false);
        else
            player->Teleport(CVector(x, y, z), false);
    }
    else if (verb == "vehicle")
    {
        int model = 0;
        in >> model;
        CVehicle* vehicle = CCheat::VehicleCheat(model);
        if (vehicle)
        {
            vehicle->m_nVehicleFlags.bHasBeenOwnedByPlayer = true;
            Command<Commands::WARP_CHAR_INTO_CAR>(CPools::GetPedRef(player), CPools::GetVehicleRef(vehicle));
        }
        else
        {
            result = "failed";
        }
    }
    else if (verb == "leavevehicle")
    {
        if (player->m_nPedFlags.bInVehicle && player->m_pVehicle)
            Command<Commands::WARP_CHAR_FROM_CAR_TO_COORD>(CPools::GetPedRef(player),
                player->m_pVehicle->GetPosition().x + 3.0f, player->m_pVehicle->GetPosition().y,
                player->m_pVehicle->GetPosition().z);
        else
            result = "not in vehicle";
    }
    else if (verb == "heal")
    {
        player->m_fHealth = player->m_fMaxHealth;
    }
    else if (verb == "kill")
    {
        player->m_fHealth = 0.0f;
    }
    else if (verb == "skipcutscene")
    {
        if (CCutsceneMgr::ms_running)
            CCutsceneSkipVote::PressSkip();
        else
            result = "no cutscene";
    }
    else
    {
        result = "unknown command";
    }

    ms_commandLog.push_back(line + " -> " + result);
    Event("command", "\"cmd\":\"" + JsonEscape(line) + "\",\"result\":\"" + result + "\"");
    if (ms_commandLog.size() > 30)
        ms_commandLog.pop_front();
}
