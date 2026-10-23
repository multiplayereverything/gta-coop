#include "stdafx.h"
#include "CAreaConsistency.h"
#include "CAutoTest.h"

void CAreaConsistency::Process()
{
    static uint32_t mismatchSince = 0;

    CPlayerPed* player = FindPlayerPed(0);
    // scenes, fades and cutscenes switch the area on purpose (and players are hidden then)
    if (!player || !player->m_matrix || CCutsceneMgr::ms_running || TheCamera.m_bWideScreenOn ||
        TheCamera.m_fFadeAlpha > 0.0f || CPad::GetPad(0)->DisablePlayerControls)
    {
        mismatchSince = 0;
        return;
    }

    // interiors sit ~1000 m up in their own area; nothing indoors is below z 500
    bool outside = player->GetPosition().z < 500.0f;
    int wanted = outside ? 0 : player->m_nAreaCode;
    if (CGame::currArea == wanted && player->m_nAreaCode == wanted)
    {
        mismatchSince = 0;
        return;
    }
    if (!outside && wanted == 0)  // inside but the ped's own area is unknown: nothing safe to do
        return;

    // a script can switch the area a moment before it moves the player: act only on a lasting mismatch
    uint32_t now = CTimer::m_snTimeInMilliseconds;
    if (mismatchSince == 0)
    {
        mismatchSince = now;
        return;
    }
    if (now - mismatchSince < 1500)
        return;
    mismatchSince = 0;

    CAutoTest::Event("area_corrected", "\"from\":" + std::to_string(CGame::currArea) + ",\"to\":" + std::to_string(wanted));
    Command<Commands::SET_AREA_VISIBLE>(wanted);
    Command<Commands::SET_CHAR_AREA_VISIBLE>(CPools::GetPedRef(player), wanted);
}
