#include "stdafx.h"
#include "CCutscenePlayerHider.h"
#include "CAutoTest.h"
#include <unordered_set>

static std::unordered_set<CPed*> ms_hidden;  // only compared against live peds, never dereferenced

int CCutscenePlayerHider::GetHiddenCount()
{
    return (int)ms_hidden.size();
}

void CCutscenePlayerHider::Process()
{
    bool hide = CCutsceneMgr::ms_running || TheCamera.m_bWideScreenOn;

    if (hide)
    {
        bool hidNew = false;
        for (CNetworkPlayer* networkPlayer : CNetworkPlayerManager::m_pPlayers)
        {
            CPed* ped = networkPlayer->m_pPed;
            if (ped && ped->m_bIsVisible)
            {
                ped->m_bIsVisible = false;
                ms_hidden.insert(ped);
                hidNew = true;
            }
        }
        if (hidNew)
            CAutoTest::Event("players_hidden", "\"count\":" + std::to_string(ms_hidden.size()));
        return;
    }

    if (ms_hidden.empty())
        return;

    for (CNetworkPlayer* networkPlayer : CNetworkPlayerManager::m_pPlayers)
    {
        CPed* ped = networkPlayer->m_pPed;
        if (ped && ms_hidden.count(ped))
            ped->m_bIsVisible = true;
    }
    CAutoTest::Event("players_shown", "\"count\":" + std::to_string(ms_hidden.size()));
    ms_hidden.clear();
}
