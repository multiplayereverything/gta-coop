#include "stdafx.h"
#include "CMissionDeathCheck.h"
#include <unordered_set>

static std::unordered_set<CPed*> ms_aliveThisMission;  // only compared, never dereferenced

void CMissionDeathCheck::Process()
{
    if (!CTheScripts::IsPlayerOnAMission())
    {
        ms_aliveThisMission.clear();
        return;
    }
    for (CNetworkPlayer* networkPlayer : CNetworkPlayerManager::m_pPlayers)
    {
        CPed* ped = networkPlayer->m_pPed;
        // a dead player's ped can still show an idle state with 0 health until it falls
        if (ped && ped->m_fHealth > 0.0f && ped->m_ePedState != PEDSTATE_DIE && ped->m_ePedState != PEDSTATE_DEAD &&
            ped->m_ePedState != PEDSTATE_ARRESTED)
            ms_aliveThisMission.insert(ped);
    }
}

bool CMissionDeathCheck::WasAliveThisMission(CPed* ped)
{
    return ms_aliveThisMission.count(ped) != 0;
}
