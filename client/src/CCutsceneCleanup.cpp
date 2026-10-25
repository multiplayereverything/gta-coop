#include "stdafx.h"
#include "CCutsceneCleanup.h"
#include "COpCodeSync.h"
#include "CAutoTest.h"

static void ProcessProofs()
{
    static bool protecting = false;
    static bool bullet, fire, collision, melee, explosion;
    CPlayerPed* player = FindPlayerPed(0);
    bool want = CCutsceneMgr::ms_running && player && player->m_fHealth > 0.0f &&
                CWorld::Players[0].m_nPlayerState == PLAYERSTATE_PLAYING;

    if (want && !protecting)
    {
        auto& f = player->m_nPhysicalFlags;
        bullet = f.bBulletProof; fire = f.bFireProof; collision = f.bCollisionProof;
        melee = f.bMeleeProof; explosion = f.bExplosionProof;
        f.bBulletProof = f.bFireProof = f.bCollisionProof = f.bMeleeProof = f.bExplosionProof = true;
        protecting = true;
    }
    else if (!want && protecting)
    {
        if (player)
        {
            auto& f = player->m_nPhysicalFlags;
            f.bBulletProof = bullet; f.bFireProof = fire; f.bCollisionProof = collision;
            f.bMeleeProof = melee; f.bExplosionProof = explosion;
        }
        protecting = false;
    }
}

void CCutsceneCleanup::Process()
{
    ProcessProofs();

    static bool wasOnMission = false;
    static uint32_t endedAt = 0;
    static char endedName[8];
    bool onMission = CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
    uint32_t now = GetTickCount();
    if (wasOnMission && !onMission)
    {
        endedAt = now ? now : 1;
        // only the cutscene the mission left behind: one a newly launched mission loads is its own
        memcpy(endedName, CCutsceneMgr::ms_cutsceneName, 8);
        if (!CCutsceneMgr::ms_running && CCutsceneMgr::ms_cutsceneLoadStatus == 0)
            endedName[0] = 0;
    }
    wasOnMission = onMission;

    // the mission's own cleanup gets a moment; a new mission starting meanwhile owns whatever is loaded
    if (!endedAt || onMission || now - endedAt < 1000)
    {
        if (onMission)
            endedAt = 0;
        return;
    }
    endedAt = 0;

    if (!endedName[0] || memcmp(endedName, CCutsceneMgr::ms_cutsceneName, 8) != 0 ||
        (!CCutsceneMgr::ms_running && CCutsceneMgr::ms_cutsceneLoadStatus == 0))
        return;

    // a partner still waiting for that cutscene to load would start it with no mission left to end it
    COpCodeSync::ms_bLoadingCutscene = false;
    CAutoTest::Event("cutscene_orphan_cleared", "\"name\":\"" + std::string(CCutsceneMgr::ms_cutsceneName, 0, 8) +
                                                    "\",\"running\":" + (CCutsceneMgr::ms_running ? "true" : "false"));
    if (CCutsceneMgr::ms_running)
    {
        CCutsceneMgr::ms_wasCutsceneSkipped = true;
        CCutsceneMgr::FinishCutscene();
    }
    CCutsceneMgr::DeleteCutsceneData();
}
