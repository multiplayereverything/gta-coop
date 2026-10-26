#include "stdafx.h"
#include "CPlaytestReport.h"
#include "UI/CChat.h"
#include <filesystem>
#include <fstream>
#include <ctime>

namespace fs = std::filesystem;

static fs::path GameFolder()
{
    char exe[MAX_PATH]{};
    GetModuleFileNameA(nullptr, exe, MAX_PATH);
    return fs::path(exe).parent_path();
}

static std::string Narrow(const std::wstring& w)
{
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    std::string s(n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), s.data(), n, nullptr, nullptr);
    return s;
}

static std::string MissionScriptName()
{
    for (CRunningScript* s = CTheScripts::pActiveScripts; s; s = s->m_pNext)
        if (s->m_bIsMission && strncmp(s->m_szName, "coopand", 7) != 0)
            return std::string(s->m_szName, strnlen(s->m_szName, 8));
    return "";
}

static std::string NewestCrashLog()
{
    std::error_code ec;
    fs::path newest;
    fs::file_time_type newestTime{};
    for (const auto& e : fs::directory_iterator(GameFolder() / "CoopAndreas_crashes", ec))
        if (e.path().extension() == ".log" && (newest.empty() || e.last_write_time(ec) > newestTime))
        {
            newest = e.path();
            newestTime = e.last_write_time(ec);
        }
    return newest.empty() ? "none" : newest.filename().string();
}

bool CPlaytestReport::HandleChatCommand(const std::wstring& line)
{
    if (line.rfind(L"/report", 0) != 0)
        return false;

    std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_s(&tm, &t);
    char stamp[32];
    std::strftime(stamp, sizeof(stamp), "%Y-%m-%d_%H-%M-%S", &tm);

    fs::path dir = GameFolder() / "CoopAndreas_reports";
    std::error_code ec;
    fs::create_directories(dir, ec);
    fs::path file = dir / (std::string("report-") + stamp + ".txt");

    std::ofstream o(file, std::ios::binary);
    std::wstring what = line.size() > 7 ? line.substr(7) : L"";
    what.erase(0, what.find_first_not_of(L' ') == std::wstring::npos ? what.size() : what.find_first_not_of(L' '));
    o << "CoopAndreas playtest report " << stamp << "\r\n";
    o << "What happened: " << Narrow(what) << "\r\n\r\n";
    o << "Me: " << CLocalPlayer::m_Name << (CLocalPlayer::m_bIsHost ? " (host)" : "") << "\r\n";
    bool onMission = CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
    o << "On a mission: " << (onMission ? "yes" : "no") << ", mission script: " << MissionScriptName()
      << ", cutscene: " << (CCutsceneMgr::ms_running ? std::string(CCutsceneMgr::ms_cutsceneName, 0, 8) : "none") << "\r\n";
    if (CPlayerPed* me = FindPlayerPed(0))
    {
        CVector p = me->GetPosition();
        o << "Position: " << p.x << " " << p.y << " " << p.z << ", interior " << (int)me->m_nAreaCode << ", health "
          << me->m_fHealth << ", vehicle "
          << (me->m_nPedFlags.bInVehicle && me->m_pVehicle ? std::to_string(me->m_pVehicle->m_nModelIndex) : "none") << "\r\n";
    }
    o << "Network: ping " << CNetwork::GetRTT() << " ms, lost packets " << CNetwork::GetDroppedRatio() << " %\r\n";
    o << "Other players:\r\n";
    for (CNetworkPlayer* np : CNetworkPlayerManager::m_pPlayers)
    {
        o << "  " << np->GetName() << (np->m_bIsHost ? " (host)" : "") << ": ping " << np->m_nRTT << " ms"
          << (np->m_bConnectionLost ? ", CONNECTION LOST" : "");
        if (np->m_pPed && FindPlayerPed(0))
            o << ", " << (int)(np->m_pPed->GetPosition() - FindPlayerPed(0)->GetPosition()).Magnitude() << " m away, health "
              << np->m_pPed->m_fHealth;
        o << "\r\n";
    }
    o << "Newest crash log: " << NewestCrashLog() << "\r\n";
    o.close();

    CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}Report saved: CoopAndreas_reports\\%s. Send it (and any crash log) "
                      "to whoever fixes the mod.", file.filename().string().c_str());
    return true;
}
