#include "stdafx.h"
#include <shlobj.h>
#include "CAutoTest.h"
#include "Hooks/VehicleHooks.h"
#include "CRadarSync.h"
#include "CCutsceneSkipVote.h"
#include "COpCodeSync.h"
#include "CCoopPerf.h"
#include "CMissionMarkerSync.h"
#include "CMissionPickupSync.h"
#include "CMissionFireSync.h"
#include "CMissionTrainSync.h"
#include "CSaveSync.h"
#include "CUserTrackSync.h"
#include "CPlaytestReport.h"
#include <game_sa/CTagManager.h>
#include <CStats.h>
#include <CTheZones.h>
#include <CAERadioTrackManager.h>
#include <CAudioEngine.h>
#include <CGenericGameStorage.h>
#include <CClothes.h>
#include <CMessages.h>
#include <C3dMarkers.h>
#include <CFireManager.h>
#include <CPickups.h>
#include <CCheckpoints.h>
#include <CEntryExitManager.h>
#include <deque>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace fs = std::filesystem;

static fs::path ms_dir;
static int ms_nAutoLoadSlot = -1;  // -autoload <slot>
static std::string ms_docsDir;  // test games' own Documents\GTA San Andreas User Files, see ApplyTestUserDir
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

// -autohide: the game window can never be activated and sits behind every other window, so a test run never pops
// up over (or takes keyboard focus from) whatever the user is doing; ProcessGame minimizes it once the game runs
// (minimizing during startup leaves a 0x0 client area and the frontend never advances). Done by patching
// gta_sa.exe's own imports of the user32 window calls, plus a CBT hook that vetoes activation from anywhere
// (d3d9 and other modules activate the window through their own imports).
static HWND ms_hHiddenWindow = NULL;
static HHOOK ms_hActivationHook = NULL;

static LRESULT CALLBACK ActivationHook_Hidden(int code, WPARAM wParam, LPARAM lParam)
{
    if (code == HCBT_ACTIVATE)  // any window of the game thread
        return 1;
    return CallNextHookEx(ms_hActivationHook, code, wParam, lParam);
}

static HWND WINAPI CreateWindowExA_Hidden(DWORD exStyle, LPCSTR cls, LPCSTR name, DWORD style, int x, int y, int w, int h,
    HWND parent, HMENU menu, HINSTANCE inst, LPVOID param)
{
    if (!ms_hActivationHook)
        ms_hActivationHook = SetWindowsHookExA(WH_CBT, ActivationHook_Hidden, NULL, GetCurrentThreadId());
    HWND hWnd = CreateWindowExA(exStyle | WS_EX_NOACTIVATE, cls, name, style & ~WS_VISIBLE, x, y, w, h, parent, menu, inst, param);
    char className[64] = "";
    if (hWnd && !parent && GetClassNameA(hWnd, className, sizeof(className)) && !strcmp(className, "Grand theft auto San Andreas"))
        ms_hHiddenWindow = hWnd;
    return hWnd;
}
static BOOL WINAPI ShowWindow_Hidden(HWND hWnd, int nCmdShow)
{
    if (nCmdShow == SW_HIDE)
        return ShowWindow(hWnd, SW_HIDE);
    BOOL result = ShowWindow(hWnd, IsIconic(hWnd) ? SW_SHOWMINNOACTIVE : SW_SHOWNOACTIVATE);
    SetWindowPos(hWnd, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    return result;
}
static void __cdecl UnderWaterEffect_Hidden() {}
static BOOL WINAPI SetForegroundWindow_Hidden(HWND) { return TRUE; }
static HWND WINAPI SetFocus_Hidden(HWND) { return GetFocus(); }
static HWND WINAPI SetActiveWindow_Hidden(HWND) { return GetActiveWindow(); }
static BOOL WINAPI BringWindowToTop_Hidden(HWND) { return TRUE; }

static int PatchGameImport(const char* name, void* replacement, const char* dll = "user32.dll")
{
    auto base = (uint8_t*)GetModuleHandleA(NULL);
    auto nt = (IMAGE_NT_HEADERS*)(base + ((IMAGE_DOS_HEADER*)base)->e_lfanew);
    auto& dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    HMODULE module = GetModuleHandleA(dll);
    if (!module)
        module = LoadLibraryA(dll);
    void* target = module ? (void*)GetProcAddress(module, name) : nullptr;
    int patched = 0;
    if (!dir.VirtualAddress || !target)
        return 0;
    for (auto imp = (IMAGE_IMPORT_DESCRIPTOR*)(base + dir.VirtualAddress); imp->Name; imp++)
    {
        for (auto thunk = (IMAGE_THUNK_DATA*)(base + imp->FirstThunk); thunk->u1.Function; thunk++)
        {
            if ((void*)thunk->u1.Function != target)
                continue;
            DWORD old;
            VirtualProtect(&thunk->u1.Function, sizeof(void*), PAGE_READWRITE, &old);
            thunk->u1.Function = (uintptr_t)replacement;
            VirtualProtect(&thunk->u1.Function, sizeof(void*), old, &old);
            patched++;
        }
    }
    return patched;
}

// test games keep their saves, settings and user tracks in their own folder: every copy of the game would otherwise
// share the player's real Documents\GTA San Andreas User Files. The game gets that folder from GetUserFilesFolder
// (0x744FB0, behind the copy protection), called from three places: each call is wrapped and the folder it filled
// (0xC92368) replaced by the test folder before anything uses it. From the very first call - switching the folder
// while the game was running crashed its file handling.
static char* __cdecl GetUserFilesFolder_Test()
{
    char* folder = plugin::CallAndReturn<char*, 0x744FB0>();
    if (!ms_docsDir.empty())
    {
        // a fresh folder like a real one: settings and the user track index (the game crashed on missing ones);
        // the real folder is only read
        std::error_code ec;
        fs::create_directories(fs::path(ms_docsDir) / "User Tracks", ec);
        for (const char* name : {"gta_sa.set", "sa-ufiles.dat", "sa-utrax.dat"})
        {
            if (!fs::exists(fs::path(ms_docsDir) / name, ec))
                fs::copy_file(fs::path(folder) / name, fs::path(ms_docsDir) / name, ec);
        }
        strncpy_s((char*)0xC92368, 256, ms_docsDir.c_str(), _TRUNCATE);
        folder = (char*)0xC92368;
    }
    return folder;
}
static void __cdecl UpdatePads_Hook();

// test runs only: when the game loop stops (a hang, no crash log), write where the main thread is stuck to hang.txt:
// EIP and the return addresses found on its stack, with the module they belong to
static DWORD ms_nMainThreadId = 0;
static volatile LONG ms_nHeartbeat = 0;

static std::string DescribeAddress(DWORD address)
{
    char text[300];
    HMODULE module = nullptr;
    char name[MAX_PATH] = "?";
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)address, &module))
    {
        GetModuleFileNameA(module, name, sizeof(name));
        snprintf(text, sizeof(text), "0x%08X %s+0x%X", address, fs::path(name).filename().string().c_str(), address - (DWORD)module);
    }
    else
        snprintf(text, sizeof(text), "0x%08X", address);
    return text;
}

static DWORD WINAPI HangWatchdog(LPVOID)
{
    LONG last = -1;
    int staleSeconds = 0, reports = 0;
    while (reports < 3)
    {
        Sleep(1000);
        LONG now = ms_nHeartbeat;
        staleSeconds = (now == last) ? staleSeconds + 1 : 0;
        last = now;
        if (now == 0 || staleSeconds < 8)
            continue;
        staleSeconds = 0;
        reports++;

        HANDLE thread = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT, FALSE, ms_nMainThreadId);
        if (!thread)
            continue;
        CONTEXT ctx{};
        ctx.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
        std::ostringstream out;
        if (SuspendThread(thread) != (DWORD)-1)
        {
            if (GetThreadContext(thread, &ctx))
            {
                out << "hang (no frame for 8 s) EIP " << DescribeAddress(ctx.Eip) << " ESP 0x" << std::hex << ctx.Esp << std::dec << '\n';
                DWORD* stack = (DWORD*)ctx.Esp;
                for (int i = 0; i < 1024 && !IsBadReadPtr(stack + i, 4); i++)
                {
                    DWORD v = stack[i];
                    HMODULE m = nullptr;
                    if (v > 0x10000 && GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)v, &m))
                        out << "  [esp+" << i * 4 << "] " << DescribeAddress(v) << '\n';
                }
            }
            ResumeThread(thread);
        }
        CloseHandle(thread);
        std::ofstream file(ms_dir / "hang.txt", std::ios::app);
        file << out.str() << '\n';
    }
    return 0;
}

static void StartHangWatchdog()
{
    ms_nMainThreadId = GetCurrentThreadId();
    CreateThread(nullptr, 0, HangWatchdog, nullptr, 0, nullptr);
}

void CAutoTest::Init()
{
    const char* cmd = GetCommandLineA();
    if (!strstr(cmd, "--autotest"))
        return;

    ms_bEnabled = true;
    patch::RedirectCall(0x53BEE6, UpdatePads_Hook);

    if (strstr(cmd, "-autohide"))
    {
        // hidden test games are minimized: the underwater screen effect (CPostEffects, 0x7039C0) reads the screen picture
        // a minimized window does not have and crashed whenever a test player was in water. Test runs only.
        patch::RedirectCall(0x70529C, UnderWaterEffect_Hidden);  // call CPostEffects::UnderWaterRipple (E8 -> 0x7039C0, checked)
        PatchGameImport("CreateWindowExA", CreateWindowExA_Hidden);
        PatchGameImport("ShowWindow", ShowWindow_Hidden);
        PatchGameImport("SetForegroundWindow", SetForegroundWindow_Hidden);
        PatchGameImport("SetFocus", SetFocus_Hidden);
        PatchGameImport("SetActiveWindow", SetActiveWindow_Hidden);
        PatchGameImport("BringWindowToTop", BringWindowToTop_Hidden);
    }

    if (const char* v = GetArg(cmd, "-autoip"))
        CopyArg(v, ms_ip, sizeof(ms_ip));
    if (const char* v = GetArg(cmd, "-autoload"))
        ms_nAutoLoadSlot = atoi(v);
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
    StartHangWatchdog();
    // short, like the real one: the game builds file names from it in small fixed-size buffers
    char temp[MAX_PATH] = "";
    GetTempPathA(MAX_PATH, temp);
    ms_docsDir = (fs::path(temp) / ("coopt-" + ms_dir.filename().string()) / "GTA San Andreas User Files").string();
    for (uintptr_t site : {0x747470, 0x538860, 0x619075})  // every call of GetUserFilesFolder
        patch::RedirectCall(site, GetUserFilesFolder_Test);

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

// the running mission script on the host (non-hosts only get the on-mission flag). Also counts helper scripts a
// mission started (not flagged m_bIsMission) whose code lives in the mission block (ScriptSpace + 200000,
// 69000 bytes): launching another mission overwrites it and they crash the script engine (gta_sa+0x6952A)
static CRunningScript* FindMissionScript()
{
    const uint8_t* missionBlock = (const uint8_t*)CTheScripts::ScriptSpace + 200000;
    // the mission thread itself first: a helper thread it started (no name, e.g. in Deconstruction) came first in the
    // list, so passmission jumped the helper and the mission never passed
    for (CRunningScript* s = CTheScripts::pActiveScripts; s; s = s->m_pNext)
        if (s->m_bIsMission && strncmp(s->m_szName, "coopand", 7) != 0)
            return s;
    for (CRunningScript* s = CTheScripts::pActiveScripts; s; s = s->m_pNext)
    {
        if (strncmp(s->m_szName, "coopand", 7) == 0)
            continue;
        // also helper threads a mission started: they run code inside the mission block (their base may be elsewhere)
        if ((s->m_pBaseIP >= missionBlock && s->m_pBaseIP < missionBlock + 69000) ||
            (s->m_pCurrentIP >= missionBlock && s->m_pCurrentIP < missionBlock + 69000))
            return s;
    }
    return nullptr;
}

static CRunningScript* ms_pPassLabelScript = nullptr;
static int ms_nPassLabel = 0;

void CAutoTest::SetPassLabel(CRunningScript* script, int label)
{
    ms_pPassLabelScript = script;
    ms_nPassLabel = label;
}

static std::string GetMissionScriptName()
{
    CRunningScript* s = FindMissionScript();
    if (!s)
        return "";
    char name[9]{};
    memcpy(name, s->m_szName, 8);
    return name;
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
    static std::string result, script;

    // the mission script names itself a moment after it launches
    std::string nowScript = GetMissionScriptName();
    if (nowScript != script)
    {
        script = nowScript;
        if (!script.empty())
            Event("mission_script", "\"script\":\"" + JsonEscape(script) + "\",\"synced\":" +
                                        (COpCodeSync::IsScriptSynced(FindMissionScript()) ? "true" : "false"));
    }

    bool nowOnMission = CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
    if (nowOnMission != onMission)
    {
        onMission = nowOnMission;
        if (onMission)
            Event("mission_started", "\"script\":\"" + JsonEscape(GetMissionScriptName()) + "\",\"host\":" +
                                         (CLocalPlayer::m_bIsHost ? "true" : "false"));
        else
        {
            Event("mission_ended");
            ms_bPassRequested = false;
            ms_pPassLabelScript = nullptr;  // the script slot gets reused by the next mission
        }
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
    static bool menu = false;
    if (FrontEndMenuManager.m_bMenuActive != menu)
    {
        menu = FrontEndMenuManager.m_bMenuActive;
        Event(menu ? "menu_opened" : "menu_closed", "\"page\":" + std::to_string(FrontEndMenuManager.m_nCurrentMenuPage));
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
    InterlockedIncrement(&ms_nHeartbeat);

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

    // -autoload <slot>: start by loading that saved game (as Load Game in the menu), otherwise a new game
    if (ms_nAutoLoadSlot >= 0 && CGenericGameStorage::CheckSlotDataValid(ms_nAutoLoadSlot, false))
    {
        Event("menu_load_game", "\"slot\":" + std::to_string(ms_nAutoLoadSlot));
        pMenu->DoSettingsBeforeStartingAGame();
        pMenu->m_bWantToLoad = true;  // = m_bLoadingData: CGame::InitialiseWhenRestarting loads the slot
        return;
    }
    ms_commandLog.push_back("menu: starting new game");
    Event("menu_new_game");
    pMenu->DoSettingsBeforeStartingAGame();
}

// press <button> [ms]: held on pad 0 until the deadline, then released (so "just pressed" checks fire once)
static std::string ms_pressButton;
static uint32_t ms_nPressUntil = 0;

static signed short* PadButton(CControllerState& s, const std::string& name)
{
    if (name == "cross") return &s.ButtonCross;          // sprint / accelerate / shop: buy
    if (name == "triangle") return &s.ButtonTriangle;    // enter/exit vehicle / shop: leave
    if (name == "square") return &s.ButtonSquare;
    if (name == "circle") return &s.ButtonCircle;
    if (name == "up") return &s.DPadUp;
    if (name == "down") return &s.DPadDown;
    if (name == "left") return &s.DPadLeft;
    if (name == "right") return &s.DPadRight;
    if (name == "r1") return &s.RightShoulder1;
    if (name == "l1") return &s.LeftShoulder1;
    if (name == "r3") return &s.ShockButtonR;          // in a taxi/police car/ambulance/fire truck: start the side job
    return nullptr;
}

// CGame::Process reads the pads itself (call to CPad::UpdatePads at 0x53BEE6): apply simulated buttons right after,
// before scripts and the player read them
static void __cdecl UpdatePads_Hook()
{
    CPad::UpdatePads();
    CAutoTest::ProcessPad();
}

void CAutoTest::ProcessPad()
{
    if (!ms_bEnabled || ms_pressButton.empty())
        return;
    CPad* pad = CPad::GetPad(0);
    if ((int)(ms_nPressUntil - GetTickCount()) > 0)
    {
        // several at once with '+' (press fwd+cross 3000: sprint); fwd/walkfwd/back/turnl/turnr are the left stick
        std::stringstream names(ms_pressButton);
        std::string name;
        while (std::getline(names, name, '+'))
        {
            if (name == "fwd") pad->NewState.LeftStickY = -128;
            else if (name == "walkfwd") pad->NewState.LeftStickY = -40;
            else if (name == "back") pad->NewState.LeftStickY = 128;
            else if (name == "turnl") pad->NewState.LeftStickX = -128;
            else if (name == "turnr") pad->NewState.LeftStickX = 128;
            else if (signed short* b = PadButton(pad->NewState, name))
                *b = 255;
        }
    }
    else
        ms_pressButton.clear();
}

// Animation probe for coop-anything's animcheck (toolkit-coop-anything/tools/animcheck, format in its FORMAT.md):
// every player as this game shows it - the local CJ and each other player's CJ - 20 times a second, so animcheck
// can compare a player's own body with how the others see it (sliding, T-pose, floating, wrong animation/pose).
// "animprobe on" starts autotest/<dir>/anim.probe.jsonl, "animprobe off" stops it.
static bool ms_bAnimProbe = false;

// collectibles left in the world (953 oyster, 954 horseshoe, 1253 snapshot), for the collectibles tests
static int CountPickups(int model)
{
    int n = 0;
    for (int i = 0; i < MAX_NUM_PICKUPS; i++)
        if (CPickups::aPickUps[i].m_nPickupType != PICKUP_NONE && CPickups::aPickUps[i].m_nModelIndex == model &&
            !CPickups::aPickUps[i].m_nFlags.bDisabled)
            n++;
    return n;
}

static void WriteProbeActor(std::ostringstream& o, CPed* ped, uint32_t ref)
{
    static const std::pair<const char*, unsigned> bones[] = {
        {"pelvis", 2}, {"spine", 3}, {"neck", 5}, {"head", 8},
        {"upperarm_r", 22}, {"forearm_r", 23}, {"hand_r", 25}, {"upperarm_l", 32}, {"forearm_l", 33}, {"hand_l", 35},
        {"calf_l", 42}, {"foot_l", 44}, {"calf_r", 52}, {"foot_r", 54}};
    CVector p = ped->GetPosition();
    bool inCar = ped->m_nPedFlags.bInVehicle && ped->m_pVehicle;
    bool dead = ped->m_fHealth <= 0.0f || ped->m_ePedState == PEDSTATE_DIE || ped->m_ePedState == PEDSTATE_DEAD;
    // off screen (the game does not animate it, its bones collapse), hidden (cutscene) or seated in a car:
    // animcheck skips the body checks, position is still compared
    bool valid = ped->m_pRwClump && ped->m_bIsVisible && !inCar && ped->GetIsOnScreen();
    o << "{\"ref\":" << ref << ",\"player\":true,\"pos\":[" << p.x << "," << p.y << "," << p.z << "],\"rot\":[0,0,"
      << ped->GetHeading() << "],\"cell\":" << (int)ped->m_nAreaCode << ",\"dead\":" << (dead ? "true" : "false")
      << ",\"valid3d\":" << (valid ? "true" : "false") << ",\"weapon\":{\"out\":"
      << (ped->m_aWeapons[ped->m_nActiveWeaponSlot].m_eWeaponType != WEAPON_UNARMED ? "true" : "false")
      << ",\"form\":" << (int)ped->m_aWeapons[ped->m_nActiveWeaponSlot].m_eWeaponType << "}";
    if (ped->m_pRwClump)
    {
        // animation ids below 191 are the shared ped/move table (plugin-sdk ePedAnims.h), others are "group:id"
        o << ",\"anim\":{\"seqs\":[";
        bool first = true;
        for (CAnimBlendAssociation* a = RpAnimBlendClumpGetFirstAssociation(ped->m_pRwClump); a;
             a = RpAnimBlendGetNextAssociation(a))
        {
            if (a->m_fBlendAmount <= 0.01f)
                continue;
            o << (first ? "" : ",") << "{\"slot\":" << ((a->m_nFlags & 0x10) ? 1 : 0) << ",\"group\":";
            if (a->m_nAnimId >= 0 && a->m_nAnimId < 191)
                o << a->m_nAnimId;
            else
                o << "\"" << a->m_nAnimGroup << ":" << a->m_nAnimId << "\"";
            o << ",\"state\":1,\"weight\":" << a->m_fBlendAmount << "}";
            first = false;
        }
        o << "]},\"skel\":{\"preRender\":" << (int)ped->m_nPedFlags.bCalledPreRender;
        if (RpHAnimHierarchy* h = GetAnimHierarchyFromSkinClump(ped->m_pRwClump))
        {
            // diagnostic: the hierarchy's own matrices after an update, next to GetBonePosition below
            ped->UpdateRpHAnim();
            for (unsigned id : {2u, 8u, 35u})
            {
                int i = RpHAnimIDGetIndex(h, id);
                RwV3d m = i >= 0 ? h->pMatrixArray[i].pos : RwV3d{};
                o << ",\"m" << id << "\":[" << m.x << "," << m.y << "," << m.z << "]";
            }
        }
        o << "},\"bones\":{";
        first = true;
        for (auto& [name, id] : bones)
        {
            RwV3d b{};
            ped->GetBonePosition(b, id, true);  // true: without a skin update every bone read as the root
            o << (first ? "" : ",") << "\"" << name << "\":[" << b.x << "," << b.y << "," << b.z << "]";
            first = false;
        }
        o << "}";
    }
    o << "}";
}

static void WriteAnimProbe(const fs::path& dir)
{
    static uint32_t last = 0;
    uint32_t now = GetTickCount();  // one clock for every game on this PC (and the status tick), so animcheck lines them up
    if (!ms_bAnimProbe || now - last < 50)
        return;
    last = now;
    CPlayerPed* me = FindPlayerPed(0);
    if (!me || !CNetwork::m_bAuthenticated)
        return;
    std::ostringstream o;
    o << std::fixed << std::setprecision(3) << "{\"machine\":\"" << dir.filename().string() << "\",\"t_ms\":" << now
      << ",\"rx_ms\":" << now << ",\"actors\":[";
    WriteProbeActor(o, me, CNetworkPlayerManager::m_localPlayerId.value());
    for (CNetworkPlayer* np : CNetworkPlayerManager::m_pPlayers)
        if (np->m_pPed && np->m_pPed->m_matrix)
        {
            o << ",";
            WriteProbeActor(o, np->m_pPed, np->m_playerId.value());
        }
    o << "]}\n";
    std::ofstream f(dir / "anim.probe.jsonl", std::ios::app);
    f << o.str();
}

void CAutoTest::ProcessGame()
{
    if (!ms_bEnabled)
        return;
    InterlockedIncrement(&ms_nHeartbeat);

    static bool firstFrame = true;
    if (firstFrame)
    {
        firstFrame = false;
        Event("game_loop_running");
    }

    ms_nFrames++;

    // -autohide: minimize once the game is in-game (CoopAndreas forces ForegroundApp, so it keeps running)
    static bool minimized = false;
    static uint32_t gameFrames = 0;
    if (!minimized && ms_hHiddenWindow && ++gameFrames > 300)
    {
        minimized = true;
        ShowWindow(ms_hHiddenWindow, SW_SHOWMINNOACTIVE);
        Event("window_hidden");
    }

    DetectChanges();
    DetectMission();
    ExecuteCommands();
    WriteStatus(true);
    WriteAnimProbe(ms_dir);
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

// which car the (single) radio is tuned to: 0xB6B99C = that car's audio entity settings (entity + 0x80), set by
// CAEVehicleAudioEntity::TurnOnRadioForVehicle and cleared by TurnOffRadioForVehicle
static const char* RadioCar()
{
    uint8_t* settings = *(uint8_t**)0xB6B99C;
    if (!settings)
        return "none";
    CVehicle* vehicle = *(CVehicle**)(settings - 0x80 + 4);
    return vehicle && vehicle == FindPlayerVehicle(0, false) ? "mine" : "other";
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
           << "\",\"skipVotes\":" << CCutsceneSkipVote::GetVotes() << ",\"skipVoters\":" << CCutsceneSkipVote::GetVoters()
           << ",\"controlsDisabled\":" << (CPad::GetPad(0)->DisablePlayerControls ? "true" : "false")
           << ",\"pad\":{\"dpc\":" << CPad::GetPad(0)->DisablePlayerControls << ",\"mode\":" << CPad::GetPad(0)->Mode
           << ",\"brakes\":" << (int)CPad::GetPad(0)->bApplyBrakes << ",\"stickY\":" << CPad::GetPad(0)->NewState.LeftStickY
           << ",\"tempStickY\":" << CPad::GetPad(0)->PCTempKeyState.LeftStickY << ",\"keyW\":" << CPad::NewKeyState.standardKeys['W']
           << ",\"lalt\":" << CPad::NewKeyState.lmenu << ",\"menu\":" << (int)FrontEndMenuManager.m_bMenuActive
           << ",\"userPause\":" << (int)CTimer::m_UserPause << ",\"codePause\":" << (int)CTimer::m_CodePause
           << ",\"pedState\":" << (FindPlayerPed(0) ? (int)FindPlayerPed(0)->m_ePedState : -1)
           << ",\"task\":" << (FindPlayerPed(0) && FindPlayerPed(0)->m_pIntelligence->m_TaskMgr.GetActiveTask() ? (int)FindPlayerPed(0)->m_pIntelligence->m_TaskMgr.GetActiveTask()->GetTaskType() : -1)
           << ",\"focus\":" << (int)CWorld::PlayerInFocus << "}"
           << ",\"mirroredMarkers\":" << CMissionMarkerSync::GetMirroredCount()
           << ",\"carJitter\":" << (CNetworkVehicleManager::ms_nJitterSamples ? 100.0 * CNetworkVehicleManager::ms_nJitterBackSteps / CNetworkVehicleManager::ms_nJitterSamples : 0.0)
           << ",\"carJitterSamples\":" << CNetworkVehicleManager::ms_nJitterSamples << ",\"carSnaps\":" << CNetworkVehicleManager::ms_nSnaps
           << ",\"towing\":" << [] { int n = 0; for (CNetworkVehicle* v : CNetworkVehicleManager::m_pVehicles) if (v->m_pVehicle && v->m_pVehicle->m_pTrailer && v->m_pVehicle->m_pTrailer->m_matrix && (v->m_pVehicle->m_pTrailer->GetPosition() - v->m_pVehicle->GetPosition()).Magnitude() < 20.0f) n++; return n; }()
           << ",\"missionPickups\":" << CMissionPickupSync::GetCount() << ",\"missionFires\":" << CMissionFireSync::GetCount()
           << ",\"trainInfo\":\"" << CMissionTrainSync::Describe() << "\""
           << ",\"trains\":" << CMissionTrainSync::GetCount() << ",\"trainOffset\":" << CMissionTrainSync::GetMaxOffset()
           << ",\"userDir\":\"" << JsonEscape((const char*)0xC92368) << "\",\"savePrefix\":\"" << JsonEscape((const char*)0xC16F18) << "\""
           << ",\"userTracksReceived\":" << CUserTrackSync::GetReceivedCount()
           << ",\"radioStation\":" << (AudioEngine.IsRadioOn() ? (int)AudioEngine.GetCurrentRadioStationID() : 0)
           << ",\"zoneInfo\":\"" << [] { CPlayerPed* me = FindPlayerPed(0); CVector pos = me ? me->GetPosition() : CVector(); CZoneInfo* info = CTheZones::GetZoneInfo(&pos, nullptr); std::ostringstream o; o << std::hex << (uintptr_t)info << std::dec << " count " << *(int16_t*)0xBA1DE8 << " gangs"; for (int g = 0; info && g < 10; g++) o << " " << (int)(uint8_t)info->m_nGangDensity[g]; return o.str(); }() << "\""
           << ",\"missionBlockScripts\":\"" << [] { std::string s; const uint8_t* block = (const uint8_t*)CTheScripts::ScriptSpace + 200000; for (CRunningScript* r = CTheScripts::pActiveScripts; r; r = r->m_pNext) if (r->m_bIsMission || (r->m_pCurrentIP >= block && r->m_pCurrentIP < block + 69000)) { s += std::string(r->m_szName, strnlen(r->m_szName, 8)) + (r->m_bIsMission ? "(m) " : " "); } return s; }() << "\""
           << ",\"pools\":{\"colModel\":" << (CPools::ms_pColModelPool ? CPools::ms_pColModelPool->GetNoOfUsedSpaces() : -1) << ",\"colModelSize\":" << (CPools::ms_pColModelPool ? CPools::ms_pColModelPool->m_nSize : -1) << ",\"ped\":" << CPools::ms_pPedPool->GetNoOfUsedSpaces() << ",\"vehicle\":" << CPools::ms_pVehiclePool->GetNoOfUsedSpaces() << ",\"object\":" << CPools::ms_pObjectPool->GetNoOfUsedSpaces() << ",\"building\":" << CPools::ms_pBuildingPool->GetNoOfUsedSpaces() << ",\"vehicleStruct\":" << (CVehicleModelInfo::CVehicleStructure::m_pInfoPool ? CVehicleModelInfo::CVehicleStructure::m_pInfoPool->GetNoOfUsedSpaces() : -1) << ",\"vehicleStructSize\":" << (CVehicleModelInfo::CVehicleStructure::m_pInfoPool ? CVehicleModelInfo::CVehicleStructure::m_pInfoPool->m_nSize : -1) << "}"
           << ",\"cutsceneGate\":{\"control\":" << TheCamera.m_nWhoIsInControlOfTheCamera << ",\"camMode\":" << TheCamera.m_aCams[TheCamera.m_nActiveCam].m_nMode << ",\"loadStatus\":" << (int)CCutsceneMgr::ms_cutsceneLoadStatus << ",\"finishIn\":" << ((int)TheCamera.GetCutSceneFinishTime() - (int)CTimer::m_snTimeInMilliseconds) << "}"
           << ",\"collectibles\":{\"horseshoes\":" << CStats::GetStatValue(STAT_HORSESHOES_COLLECTED)
           << ",\"oysters\":" << CStats::GetStatValue(STAT_OYSTERS_COLLECTED) << ",\"snapshots\":" << CStats::GetStatValue(STAT_SNAPSHOTS_TAKEN)
           << ",\"tags\":" << CStats::GetStatValue(STAT_TAGS_SPRAYED) << ",\"tagsDone\":" << [] { int n = 0; for (auto& t : CTagManager::ms_tagDesc) if (t.m_pEntity && t.m_nAlpha >= 229) n++; return n; }() << ",\"pickups953\":" << CountPickups(953)
           << ",\"pickups954\":" << CountPickups(954) << ",\"pickups1253\":" << CountPickups(1253) << "}"
           << ",\"minigame\":" << (CTheScripts::bMiniGameInProgress ? "true" : "false")
           << ",\"coopUs\":{\"net\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::NET] << ",\"process\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::PROCESS] << ",\"draw\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::DRAW] << ",\"autotest\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::AUTOTEST] << ",\"peds\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::PEDS] << ",\"vehicles\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::VEHICLES] << ",\"tags\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::TAGS] << ",\"chatAndRest\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::CHAT] << ",\"playerList\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::PLAYERLIST] << ",\"checkpoint\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::CHECKPOINT] << ",\"input\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::INPUT] << ",\"version\":" << (int)CCoopPerf::ms_aLastUs[CCoopPerf::VERSION] << "}"
           << ",\"widescreen\":" << (TheCamera.m_bWideScreenOn ? "true" : "false")
           << ",\"dtorEsiClobbered\":" << g_nVehicleDtorEsiClobbered
           << ",\"radioCar\":\"" << RadioCar() << "\",\"area\":" << CGame::currArea
           << ",\"npcJitterCm\":"
           << (CNetworkPedManager::ms_nJitterSamples ? CNetworkPedManager::ms_fJitterSum / CNetworkPedManager::ms_nJitterSamples : 0.0)
           << ",\"npcJitterSamples\":" << CNetworkPedManager::ms_nJitterSamples << ",\"ownNpcJitterCm\":"
           << (CNetworkPedManager::ms_nOwnJitterSamples ? CNetworkPedManager::ms_fOwnJitterSum / CNetworkPedManager::ms_nOwnJitterSamples : 0.0);

        // objective blips: shown, not short-range (shops/contact icons are short-range), no sprite (plain markers)
        // blips[]: type 1 car, 2 char, 3 object, 4 coord; live entity position, so playthrough scripts can follow
        int blips = 0;
        std::ostringstream list;
        for (int i = 0; i < MAX_RADAR_TRACES; i++)
        {
            tRadarTrace& t = CRadar::ms_RadarTrace[i];
            if (!t.m_bInUse || t.m_nBlipDisplay == 0 || t.m_bShortRange || t.m_nRadarSprite != 0 || !CRadarSync::IsTraceVisible(i))  // only what this player sees (SetBlipVisibleTo)
                continue;
            CVector pos = t.m_vecPos;
            CEntity* entity = t.m_nBlipType == 1   ? (CEntity*)CPools::GetVehicle(t.m_nEntityHandle)
                              : t.m_nBlipType == 2 ? (CEntity*)CPools::GetPed(t.m_nEntityHandle)
                              : t.m_nBlipType == 3 ? (CEntity*)CPools::GetObject(t.m_nEntityHandle)
                                                   : nullptr;
            if (entity && entity->m_matrix)
                pos = entity->m_matrix->pos;
            std::string pickupInfo;
            if (t.m_nBlipType == 7)  // pickup: its type and model, or -1 when this game has no such pickup
            {
                int index = CPickups::GetActualPickupIndex(t.m_nEntityHandle);
                if (index != -1)
                {
                    pos = CPickups::aPickUps[index].GetPosn();
                    pickupInfo = ",\"pickupType\":" + std::to_string(CPickups::aPickUps[index].m_nPickupType) + ",\"model\":" +
                                 std::to_string(CPickups::aPickUps[index].m_nModelIndex);
                }
                else
                    pickupInfo = ",\"pickupType\":-1";
            }
            list << (blips ? "," : "") << "{\"type\":" << (int)t.m_nBlipType << ",\"colour\":" << t.m_nColour
                 << ",\"x\":" << pos.x << ",\"y\":" << pos.y << ",\"z\":" << pos.z << pickupInfo << "}";
            blips++;
        }
        js << ",\"objectiveBlips\":" << blips << ",\"blips\":[" << list.str() << "]";

        // markers[]: 3D markers drawn this moment (type 1 = the cylinders of "go here" locates and shop/entry markers)
        js << ",\"markers\":[";
        int markers = 0;
        for (int i = 0; i < 32; i++)
        {
            C3dMarker& m = C3dMarkers::m_aMarkerArray[i];
            if (!m.m_bIsUsed)
                continue;
            js << (markers++ ? "," : "") << "{\"type\":" << m.m_nType << ",\"x\":" << m.m_mat.pos.x << ",\"y\":" << m.m_mat.pos.y
               << ",\"z\":" << m.m_mat.pos.z << ",\"size\":" << m.m_fSize << "}";
        }
        js << "]";

        // checkpoints[]: race-style checkpoints (CCheckpoints, rings/arrows of races and chases)
        js << ",\"checkpoints\":[";
        int checkpoints = 0;
        for (int i = 0; i < 32; i++)
        {
            CCheckpoint& c = CCheckpoints::m_aCheckPtArray[i];
            if (!c.m_bIsUsed)
                continue;
            js << (checkpoints++ ? "," : "") << "{\"type\":" << c.m_nType << ",\"x\":" << c.m_vecPosition.x << ",\"y\":" << c.m_vecPosition.y
               << ",\"z\":" << c.m_vecPosition.z << "}";
        }
        js << "]";

        // doors[]: entry/exit markers within 40 m (house/shop doors: walking into one moves you through it)
        js << ",\"doors\":[";
        int doors = 0;
        if (CPlayerPed* me = FindPlayerPed(0); me && CEntryExitManager::mp_poolEntryExits)
        {
            for (auto e : CEntryExitManager::mp_poolEntryExits)
            {
                CVector c((e->m_recEntrance.left + e->m_recEntrance.right) / 2, (e->m_recEntrance.top + e->m_recEntrance.bottom) / 2,
                    e->m_fEntranceZ);
                if ((c - me->GetPosition()).Magnitude() > 300.0f)
                    continue;
                // where it leads: the linked entry/exit on the other side (or its exit position)
                CVector to = e->m_vecExitPos;
                if (e->m_pLink)
                    to = CVector((e->m_pLink->m_recEntrance.left + e->m_pLink->m_recEntrance.right) / 2,
                        (e->m_pLink->m_recEntrance.top + e->m_pLink->m_recEntrance.bottom) / 2, e->m_pLink->m_fEntranceZ);
                js << (doors++ ? "," : "") << "{\"name\":\"" << JsonEscape(std::string(e->m_szName, strnlen(e->m_szName, 8)))
                   << "\",\"area\":" << (int)e->m_nArea << ",\"x\":" << c.x << ",\"y\":" << c.y << ",\"z\":" << c.z
                   << ",\"tx\":" << to.x << ",\"ty\":" << to.y << ",\"tz\":" << to.z << "}";
            }
        }
        js << "]";
    }

    CPlayerPed* player = inGame ? FindPlayerPed(0) : nullptr;
    if (player && player->m_matrix)
    {
        CVector& p = player->m_matrix->pos;
        bool inVehicle = player->m_nPedFlags.bInVehicle && player->m_pVehicle;
        js << ",\"local\":{\"x\":" << p.x << ",\"y\":" << p.y << ",\"z\":" << p.z
           << ",\"health\":" << player->m_fHealth << ",\"inVehicle\":" << (inVehicle ? "true" : "false")
           << ",\"vehicleModel\":" << (inVehicle ? player->m_pVehicle->m_nModelIndex : 0)
           << ",\"interior\":" << (int)player->m_nAreaCode << ",\"money\":" << CWorld::Players[0].m_nMoney
           << ",\"wanted\":" << (FindPlayerWanted(0) ? (int)FindPlayerWanted(0)->m_nWantedLevel : 0) << "}";
    }

    js << ",\"players\":[";
    bool first = true;
    for (CNetworkPlayer* np : CNetworkPlayerManager::m_pPlayers)
    {
        js << (first ? "" : ",") << "{\"id\":" << np->m_playerId.value() << ",\"name\":\"" << JsonEscape(np->m_Name)
           << "\",\"hasPed\":" << (np->m_pPed ? "true" : "false") << ",\"isHost\":" << (np->m_bIsHost ? "true" : "false")
           << ",\"interior\":" << (np->m_pPed ? (int)np->m_pPed->m_nAreaCode : -1);
        if (np->m_pPed && np->m_pPed->m_matrix)
        {
            CVector& p = np->m_pPed->m_matrix->pos;
            js << ",\"x\":" << p.x << ",\"y\":" << p.y << ",\"z\":" << p.z;
            if (player && player->m_matrix)
                js << ",\"distance\":" << (p - player->m_matrix->pos).Magnitude();
            js << ",\"inVehicle\":" << (np->m_pPed->m_nPedFlags.bInVehicle ? "true" : "false");
            js << ",\"health\":" << np->m_pPed->m_fHealth << ",\"pedState\":" << (int)np->m_pPed->m_ePedState << ",\"connectionLost\":" << (np->m_bConnectionLost ? "true" : "false");
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
        // the same commands the chat box takes ("/report ...")
        if (CPlaytestReport::HandleChatCommand(packet.message))
            result = "command";
        else
        {
            CChat::AddPlayerChatMessage(CLocalPlayer::m_Name, packet.message);
            GetPacketFactory().Send(packet);
        }
    }
    else if (verb == "teleport")
    {
        float x = 0, y = 0, z = 0;
        in >> x >> y >> z;
        // interiors sit at z ~1000 in their own area: a target on the wrong side of a door means a fall to death
        // (test scripts acting on a status written just before a door transition)
        if ((z > 500.0f) != (player->m_nAreaCode != 0))
            result = "refused: target is on the other side of a door (area " + std::to_string(player->m_nAreaCode) + ")";
        else if (player->m_nPedFlags.bInVehicle && player->m_pVehicle)
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
            std::string kind;
            if (in >> kind && kind == "mission")  // vehicle <model> mission: like a car a mission script created
                vehicle->m_nCreatedBy = eVehicleCreatedBy::MISSION_VEHICLE;
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
        // only a living player: "healing" one that is dying half-revived it, the death/restart went wrong and the
        // next mission launch crashed (a test-only action, players cannot do this)
        if (player->m_fHealth > 0.0f && CWorld::Players[0].m_nPlayerState == PLAYERSTATE_PLAYING)
            player->m_fHealth = player->m_fMaxHealth;
        else
            result = "not alive";
    }
    else if (verb == "kill")
    {
        // kill: a deadly hit through the game's damage event (CWeapon::GenerateDamageEvent, like a gunshot; the
        // cutscene protection blocks it). kill hard: only zeroes the health - test-only, in a scripted scene the
        // player then never dies or respawns (walks around with 0 health)
        std::string how;
        in >> how;
        if (how == "hard")
            player->m_fHealth = 0.0f;
        else
            plugin::Call<0x73A530, CPed*, CEntity*, eWeaponType, int, ePedPieceTypes, int>(
                player, nullptr, WEAPON_PISTOL, 1000, (ePedPieceTypes)3 /* torso */, 0);
    }
    else if (verb == "wanted")
    {
        // wanted <level>: the local player's own wanted level (checks that it doesn't spread to the others)
        int level = 0;
        in >> level;
        Command<Commands::SET_MAX_WANTED_LEVEL>(6);
        Command<Commands::ALTER_WANTED_LEVEL>(0, level);
    }
    else if (verb == "smoothing")
    {
        // smoothing <0|1>: on-foot smoothing of NPCs synced from other players (compare jitter); resets the metric
        // smoothing <0|1> [strength]: also resets both jitter metrics
        int on = 1;
        float strength = CNetworkPedManager::ms_fSmoothingStrength;
        in >> on >> strength;
        CNetworkPedManager::ms_bSmoothing = on != 0;
        CNetworkPedManager::ms_fSmoothingStrength = strength;
        CNetworkPedManager::ms_fJitterSum = CNetworkPedManager::ms_fOwnJitterSum = 0.0;
        CNetworkPedManager::ms_nJitterSamples = CNetworkPedManager::ms_nOwnJitterSamples = 0;
        CNetworkVehicleManager::ms_bSmoothing = on != 0;  // cars driven by other players too
        CNetworkVehicleManager::ms_nJitterSamples = CNetworkVehicleManager::ms_nJitterBackSteps = CNetworkVehicleManager::ms_nSnaps = 0;
    }
    else if (verb == "enex")
    {
        // enex <name> <0|1>: open/close an entry/exit (doors the story unlocks later, e.g. CARLS, BARBERS)
        std::string name;
        int on = 1;
        in >> name >> on;
        Command<Commands::SWITCH_ENTRY_EXIT>(name.c_str(), on != 0);
    }
    else if (verb == "countpeds")
    {
        // countpeds <radius> <model> [model...]: non-player peds of those models around the player (duplicates)
        float radius = 10.0f;
        in >> radius;
        std::vector<int> models;
        for (int m; in >> m;)
            models.push_back(m);
        int count = 0;
        for (int i = 0; i < CPools::ms_pPedPool->m_nSize; i++)
        {
            CPed* ped = CPools::ms_pPedPool->GetAt(i);
            if (!ped || ped->IsPlayer() || (ped->GetPosition() - player->GetPosition()).Magnitude() > radius)
                continue;
            if (std::find(models.begin(), models.end(), (int)ped->m_nModelIndex) != models.end())
                count++;
        }
        result = "count=" + std::to_string(count);
    }
    else if (verb == "recruit")
    {
        // recruit: a Grove Street member (fam1) next to the player joins the player's group, like recruiting in play;
        // result = how many members the group has now
        Command<Commands::REQUEST_MODEL>(105);
        Command<Commands::LOAD_ALL_MODELS_NOW>();
        CVector p = player->GetPosition();
        int ped = 0, group = 0, leaders = 0, members = 0;
        Command<Commands::CREATE_CHAR>(8, 105, p.x + 2.0f, p.y, p.z, &ped);  // 8 = PEDTYPE_GANG2, Grove
        Command<Commands::GET_PLAYER_GROUP>(0, &group);
        Command<Commands::SET_GROUP_MEMBER>(group, ped);
        Command<Commands::MARK_MODEL_AS_NO_LONGER_NEEDED>(105);
        Command<Commands::GET_GROUP_SIZE>(group, &leaders, &members);
        result = "members=" + std::to_string(members);
    }
    else if (verb == "countnear")
    {
        // countnear <model> <radius>: peds of that model near me and near each other player, as this game sees them
        int model = 0;
        float radius = 10.0f;
        in >> model >> radius;
        auto count = [&](CVector c) {
            int n = 0;
            for (int i = 0; i < CPools::ms_pPedPool->m_nSize; i++)
                if (CPed* ped = CPools::ms_pPedPool->GetAt(i))
                    if (ped->m_nModelIndex == model && !ped->IsPlayer() && (ped->GetPosition() - c).Magnitude() < radius)
                        n++;
            return n;
        };
        result = "me=" + std::to_string(count(player->GetPosition()));
        for (CNetworkPlayer* np : CNetworkPlayerManager::m_pPlayers)
            if (np->m_pPed)
                result += " p" + std::to_string(np->m_playerId.value()) + "=" + std::to_string(count(np->m_pPed->GetPosition()));
    }
    else if (verb == "spraytag")
    {
        // spraytag: go to the nearest tag not fully sprayed (within 100 m) and paint it over, then share it the way a
        // spray does (WorldHooks: TagUpdate, fully sprayed). Aiming the can is the game's own code; what coop must get
        // right is that the tag turns on every game and counts for the host's mission. result = "x y z" or "none"
        CVector me = player->GetPosition();
        tTagDesc* best = nullptr;
        float bestDist = 100.0f;
        for (auto& tag : CTagManager::ms_tagDesc)
        {
            if (!tag.m_pEntity || tag.m_nAlpha >= 229)
                continue;
            float d = (tag.m_pEntity->GetPosition() - me).Magnitude();
            if (d < bestDist)
            {
                bestDist = d;
                best = &tag;
            }
        }
        if (!best)
            result = "none";
        else
        {
            CVector t = best->m_pEntity->GetPosition();
            CVector away = me - t;
            away.z = 0.0f;
            if (away.Magnitude() < 0.1f)
                away = CVector(1.0f, 0.0f, 0.0f);
            away.Normalise();
            player->Teleport(CVector(t.x + away.x * 1.8f, t.y + away.y * 1.8f, t.z), false);
            CTagManager::SetAlpha(best->m_pEntity, 255);
            Packets::World::TagUpdate packet{};
            packet.payload.bFullySprayed = true;
            packet.payload.alpha = 255;
            packet.payload.pos_x = static_cast<int16_t>(floor(t.x));
            packet.payload.pos_y = static_cast<int16_t>(floor(t.y));
            packet.payload.pos_z = static_cast<int16_t>(floor(t.z));
            GetPacketFactory().Send(packet);
            result = std::to_string(t.x) + " " + std::to_string(t.y) + " " + std::to_string(t.z);
        }
    }
    else if (verb == "nearpickup")
    {
        // nearpickup <model>: the nearest pickup of that model still in the world; result = "x y z type"
        int model = 0;
        in >> model;
        float best = 1e9f;
        CVector bestPos;
        int bestType = -1;
        for (int i = 0; i < MAX_NUM_PICKUPS; i++)
        {
            CPickup& p = CPickups::aPickUps[i];
            if (p.m_nPickupType == PICKUP_NONE || p.m_nModelIndex != model || p.m_nFlags.bDisabled)
                continue;
            float d = (p.GetPosn() - player->GetPosition()).Magnitude();
            if (d < best)
            {
                best = d;
                bestPos = p.GetPosn();
                bestType = p.m_nPickupType;
            }
        }
        result = bestType < 0 ? "none" : std::to_string(bestPos.x) + " " + std::to_string(bestPos.y) + " " +
                                             std::to_string(bestPos.z) + " " + std::to_string(bestType);
    }
    else if (verb == "pickup")
    {
        // pickup create <model> <x> <y> <z>: a mission-style pickup (create_pickup, type 3 = once);
        // pickup state: whether the script would see it collected (has_pickup_been_collected)
        static int handle = 0;
        std::string what;
        in >> what;
        if (what == "create")
        {
            int model = 0;
            float x = 0, y = 0, z = 0;
            in >> model >> x >> y >> z;
            Command<Commands::CREATE_PICKUP>(model, 3, x, y, z, &handle);
            result = "handle=" + std::to_string(handle);
        }
        else
            result = std::string("collected=") + (handle && CPickups::IsPickUpPickedUp(handle) ? "true" : "false");
    }
    else if (verb == "carto")
    {
        // carto <x> <y> <z> <heading>: put the car the player drives there, standing still (repeatable test drives)
        float x = 0, y = 0, z = 0, heading = 0;
        in >> x >> y >> z >> heading;
        if (player->m_nPedFlags.bInVehicle && player->m_pVehicle)
        {
            int car = CPools::GetVehicleRef(player->m_pVehicle);
            Command<Commands::SET_CAR_COORDINATES>(car, x, y, z);
            Command<Commands::SET_CAR_HEADING>(car, heading);
            player->m_pVehicle->m_vecMoveSpeed = CVector();
            player->m_pVehicle->m_vecTurnSpeed = CVector();
        }
        else
            result = "not in a vehicle";
    }
    else if (verb == "fire")
    {
        // fire create <x> <y> <z>: a mission fire on a spot (start_script_fire); fire state: is it out;
        // fire out <x> <y> <z>: put fires out there (like an extinguisher)
        static int handle = 0;
        std::string what;
        in >> what;
        float x = 0, y = 0, z = 0;
        in >> x >> y >> z;
        if (what == "create")
        {
            Command<Commands::START_SCRIPT_FIRE>(x, y, z, 0, 1, &handle);
            result = "handle=" + std::to_string(handle);
        }
        else if (what == "out")
            gFireManager.ExtinguishPoint(CVector(x, y, z), 4.0f);
        else
        {
            int index = handle & 0xFFFF;
            bool burning = handle && index < MAX_NUM_FIRES && gFireManager.m_aFires[index].m_nFlags.bActive;
            result = std::string("burning=") + (burning ? "true" : "false");
        }
    }
    else if (verb == "trailer")
    {
        // trailer <model>: a trailer behind the vehicle the player drives, hooked on (attach_trailer_to_cab)
        int model = 0;
        in >> model;
        if (player->m_nPedFlags.bInVehicle && player->m_pVehicle)
        {
            CVehicle* cab = player->m_pVehicle;
            CVector behind = cab->GetPosition() - cab->m_matrix->up * 10.0f;
            Command<Commands::REQUEST_MODEL>(model);
            Command<Commands::LOAD_ALL_MODELS_NOW>();
            int trailer = -1;
            Command<Commands::CREATE_CAR>(model, behind.x, behind.y, behind.z + 0.5f, &trailer);
            Command<Commands::SET_CAR_HEADING>(trailer, cab->GetHeading() * 180.0f / 3.14159265f);
            Command<Commands::ATTACH_TRAILER_TO_CAB>(trailer, CPools::GetVehicleRef(cab));
            result = "trailer=" + std::to_string(trailer);
        }
        else
            result = "not in a vehicle";
    }
    else if (verb == "train")
    {
        // train <x> <y> <z> <speed>: a mission train (create_mission_train type 9) set off at that speed;
        // train delete: delete it (delete_mission_train)
        static int train = -1;
        std::string first;
        in >> first;
        if (first == "delete")
        {
            if (train != -1)
                Command<Commands::DELETE_MISSION_TRAIN>(train);
            train = -1;
        }
        else
        {
            float x = (float)atof(first.c_str()), y = 0, z = 0, speed = 0;
            in >> y >> z >> speed;
            for (int model : {449, 537, 538, 569, 570, 590})
                Command<Commands::REQUEST_MODEL>(model);
            Command<Commands::LOAD_ALL_MODELS_NOW>();
            Command<Commands::CREATE_MISSION_TRAIN>(9, x, y, z, 1, &train);
            if (train != -1)
                Command<Commands::SET_TRAIN_CRUISE_SPEED>(train, speed);
            result = "train=" + std::to_string(train);
        }
    }
    else if (verb == "animprobe")
    {
        std::string on;
        in >> on;
        ms_bAnimProbe = on != "off";
    }
    else if (verb == "crash")
    {
        // crash: a deliberate access violation (checks the crash handling: log written, no window, game closes)
        *(volatile int*)nullptr = 0xDEAD;
    }
    else if (verb == "save")
    {
        // save <slot 0-7>: what saving in a safehouse does (the host shares it, a partner asks the host to)
        int slot = 7;
        in >> slot;
        CSaveSync::SaveFromCommand(slot);
        result = CSaveSync::SlotPath(slot);
    }
    else if (verb == "face")
    {
        // face <x> <y> <z>: turn the player toward a point, camera behind (keeps another player on screen in tests)
        float x = 0, y = 0, z = 0;
        in >> x >> y >> z;
        CVector p = player->GetPosition();
        float heading = atan2f(-(x - p.x), y - p.y);
        player->m_fCurrentRotation = player->m_fAimingRotation = heading;
        player->SetHeading(heading);
        Command<Commands::SET_CAMERA_BEHIND_PLAYER>();
    }
    else if (verb == "clothes")
    {
        // clothes <texture> <model> <bodypart>: put clothes on CJ like a mission does (e.g. BBSHORTWHT BOXINGSHORT 2)
        std::string tex, model;
        int part = 0;
        in >> tex >> model >> part;
        Command<Commands::GIVE_PLAYER_CLOTHES_OUTSIDE_SHOP>(0, tex.c_str(), model.c_str(), part);
        Command<Commands::BUILD_PLAYER_MODEL>(0);
    }
    else if (verb == "lookfrom")
    {
        // lookfrom <slot>: what loading that save does to CJ's look; result = torso clothes and fat now
        int slot = 7;
        in >> slot;
        CSaveSync::ApplyLookForSlot(slot);
        CPlayerPed* ped = FindPlayerPed(0);
        result = ped && ped->m_pPlayerData ? "torso=" + std::to_string(ped->m_pPlayerData->m_pPedClothesDesc->m_anModelKeys[0]) + " fat=" +
                                                 std::to_string((int)CStats::GetStatValue(STAT_FAT))
                                           : "no ped";
    }
    else if (verb == "fat")
    {
        // fat [0-1000]: change CJ's body (a look the save sync must keep per player); without a value: just tell
        float value = 0;
        if (in >> value)
        {
            CStats::SetStatValue(STAT_FAT, value);
            CClothes::RebuildPlayer(FindPlayerPed(0), false);
        }
        result = "fat=" + std::to_string((int)CStats::GetStatValue(STAT_FAT));
    }
    else if (verb == "loadslot")
    {
        // loadslot <slot 0-7>: load that saved game (as "Load Game" in the menu does)
        int slot = 7;
        in >> slot;
        if (CGenericGameStorage::CheckSlotDataValid(slot, false))
        {
            FrontEndMenuManager.m_bWantToLoad = true;
            FrontEndMenuManager.m_bWantToRestart = true;
        }
        else
            result = "slot not valid";
    }
    else if (verb == "radio")
    {
        // radio <1-12>: retune the car this player is in (eRadioID; 12 = user tracks)
        int station = 1;
        in >> station;
        if (player->m_nPedFlags.bInVehicle && player->m_pVehicle)
            CNetworkVehicleManager::SetOwnCarRadio(player->m_pVehicle, station);
        else
            result = "not in a vehicle";
    }
    else if (verb == "gangzone")
    {
        // gangzone <gang 0-9> <strength>: the gang's strength in the zone the player stands in (a gang war's result)
        int gang = 0, strength = 0;
        in >> gang >> strength;
        CVector pos = player->GetPosition();
        CZoneInfo* info = CTheZones::GetZoneInfo(&pos, nullptr);
        if (info && gang >= 0 && gang < 10)
            info->m_nGangDensity[gang] = (char)strength;
        else
            result = "no zone";
    }
    else if (verb == "checkpoint")
    {
        // checkpoint create <x> <y> <z> | checkpoint delete: a script race checkpoint (create_checkpoint 06D5)
        static int handle = 0;
        std::string what;
        in >> what;
        if (what == "create")
        {
            float x = 0, y = 0, z = 0;
            in >> x >> y >> z;
            if (handle)
                Command<0x06D6>(handle);
            Command<0x06D5>(1, x, y, z, x + 10.0f, y, z, 4.0f, &handle);
            result = "handle=" + std::to_string(handle);
        }
        else if (handle)
        {
            Command<0x06D6>(handle);
            handle = 0;
        }
    }
    else if (verb == "nowanted")
    {
        // test runs start late missions on a fresh save: the locked cities give an instant 4-star wanted level
        Command<Commands::SET_MAX_WANTED_LEVEL>(0);
        Command<Commands::CLEAR_WANTED_LEVEL>(0);
    }
    else if (verb == "entermissioncar")
    {
        // what a player does in most missions: get into the mission vehicle (nearest, within 80 m); a vehicle with a
        // blip is the objective ("Get on the bike"), so it wins over unmarked ones
        CVehicle* best = nullptr;
        float bestDist = 80.0f;
        for (int i = 0; i < CPools::ms_pVehiclePool->m_nSize; i++)
        {
            CVehicle* v = CPools::ms_pVehiclePool->GetAt(i);
            if (!v || v->m_nCreatedBy != eVehicleCreatedBy::MISSION_VEHICLE || v->m_pDriver)
                continue;
            float d = (v->GetPosition() - player->GetPosition()).Magnitude();
            int ref = CPools::GetVehicleRef(v);
            for (int t = 0; t < MAX_RADAR_TRACES; t++)
            {
                tRadarTrace& trace = CRadar::ms_RadarTrace[t];
                if (trace.m_bInUse && trace.m_nBlipDisplay != 0 && trace.m_nBlipType == 1 && trace.m_nEntityHandle == ref && d < 200.0f &&
                    CRadarSync::IsTraceVisible(t))
                    d -= 1000.0f;
            }
            if (d < bestDist)
            {
                bestDist = d;
                best = v;
            }
        }
        if (best && !player->m_nPedFlags.bInVehicle)
            Command<Commands::WARP_CHAR_INTO_CAR>(CPools::GetPedRef(player), CPools::GetVehicleRef(best));
        else
            result = best ? "already in a vehicle" : "no free mission vehicle within 80 m";
    }
    else if (verb == "enterpassenger")
    {
        // ride along: passenger seat of the nearest vehicle another PLAYER drives, within 15 m (never traffic)
        CVehicle* best = nullptr;
        float bestDist = 15.0f;
        for (int i = 0; i < CPools::ms_pVehiclePool->m_nSize; i++)
        {
            CVehicle* v = CPools::ms_pVehiclePool->GetAt(i);
            if (!v || !v->m_pDriver || v->m_pDriver == player || v->m_nNumPassengers >= v->m_nMaxPassengers ||
                !CNetworkPlayerManager::GetPlayer(v->m_pDriver))
                continue;
            float d = (v->GetPosition() - player->GetPosition()).Magnitude();
            if (d < bestDist)
            {
                bestDist = d;
                best = v;
            }
        }
        if (best && !player->m_nPedFlags.bInVehicle)
            Command<Commands::WARP_CHAR_INTO_CAR_AS_PASSENGER>(CPools::GetPedRef(player), CPools::GetVehicleRef(best), -1);
        else
            result = best ? "already in a vehicle" : "no driven vehicle with a free seat within 15 m";
    }
    else if (verb == "walkto")
    {
        // walkto x y z: walk there on foot and stop (shop markers want a stopped ped that walked in, not a teleport)
        float x = 0, y = 0, z = 0;
        in >> x >> y >> z;
        if (player->m_nPedFlags.bInVehicle)
            result = "in a vehicle";
        else
            Command<Commands::TASK_GO_STRAIGHT_TO_COORD>(CPools::GetPedRef(player), x, y, z, 4, 8000);
    }
    else if (verb == "press")
    {
        // press <cross|triangle|square|circle|up|down|left|right|r1|l1|r3|fwd|walkfwd|back|turnl|turnr>[+more] [ms=200]
        std::string button;
        int ms = 200;
        in >> button >> ms;
        CControllerState probe{};
        bool known = !button.empty();
        std::stringstream names(button);
        for (std::string name; std::getline(names, name, '+');)
            if (name != "fwd" && name != "walkfwd" && name != "back" && name != "turnl" && name != "turnr" &&
                !PadButton(probe, name))
                known = false;
        if (!known)
            result = "unknown button";
        else
        {
            ms_pressButton = button;
            ms_nPressUntil = GetTickCount() + (uint32_t)ms;
        }
    }
    else if (verb == "interior")
    {
        // interior <area>: what an entry marker does to the area code (partners following the host inside)
        int area = 0;
        in >> area;
        Command<Commands::SET_AREA_VISIBLE>(area);
        Command<Commands::SET_CHAR_AREA_VISIBLE>(CPools::GetPedRef(player), area);
    }
    else if (verb == "passmission")
    {
        // arms the mission's own debug skip (see ms_bPassRequested): passes through its real pass routine the
        // next time the script reaches that check; the check sits in a main loop, so it can take a moment.
        // Missions without that check register their pass routine (Coop.SetAutotestPassLabel): jump there now.
        CRunningScript* s = FindMissionScript();
        if (!s)
            result = "no mission script";
        else if (s == ms_pPassLabelScript && s->m_nSP >= 1)
        {
            // the pass routine ends with `return` back to the main routine (gosub @start -> deatharrest check ->
            // cleanup -> terminate), so drop any nested gosubs and keep the main routine's return address
            s->m_nSP = 1;
            s->m_pCurrentIP = ms_nPassLabel < 0 ? s->m_pBaseIP - ms_nPassLabel : (unsigned char*)CTheScripts::ScriptSpace + ms_nPassLabel;
            s->m_nWakeTime = 0;
            Event("debug_pass_taken", "\"script\":\"" + JsonEscape(GetMissionScriptName()) + "\",\"via\":\"label\"");
        }
        else
            ms_bPassRequested = true;
    }
    else if (verb == "failmission")
    {
        // opcode 045C fail_current_mission: the running mission script goes to its fail/cleanup path
        if (FindMissionScript())
            Command<Commands::FAIL_CURRENT_MISSION>();
        else
            result = "no mission script";
    }
    else if (verb == "startmission")
    {
        // what a mission trigger does after its marker check (e.g. scm/scripts/INT.txt)
        int id = -1;
        in >> id;
        if (!CLocalPlayer::m_bIsHost)
            result = "not host";
        else if (CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag])
            result = "already on a mission";
        // all missions share one code block in ScriptSpace: launching while another mission script runs
        // (e.g. INITIAL right after a new game) overwrites its code and crashes on a garbage opcode
        else if (FindMissionScript())
            result = "mission script running: " + GetMissionScriptName();
        // a player cannot start a mission while wasted, busted or respawning (marker triggers are off then)
        else if (player->m_fHealth <= 0.0f || CWorld::Players[0].m_nPlayerState != PLAYERSTATE_PLAYING)
            result = "player not playing (wasted, busted or respawning)";
        else if (id < 0)
            result = "usage: startmission <id>";
        else
        {
            // triggers set $onmission = 1 before launching (scm/scripts/INT.txt); some missions only set it late
            // (Ran Fa Li, Ice Cold Killa) or never (Black Project, Grove 4 Life)
            if (CTheScripts::OnAMissionFlag)
                CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag] = 1;
            Command<Commands::LOAD_AND_LAUNCH_MISSION_INTERNAL>(id);
        }
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
