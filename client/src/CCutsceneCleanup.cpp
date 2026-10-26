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

// A cutscene runs on its fly-by camera (mode 17). One whose camera went back to the player (seen after Supply Lines:
// New Model Army's cutscene camera left within a second) can never reach its end, the game stops checking the skip
// button and the mission waits forever. After 3 s like that it is finished the way a skip does it.
static void ProcessStuckCutscene()
{
    static uint32_t offCameraSince = 0;
    bool stuck = CCutsceneMgr::ms_running && CCutsceneMgr::ms_cutsceneLoadStatus == 2 &&
                 TheCamera.m_aCams[TheCamera.m_nActiveCam].m_nMode != 17;
    if (!stuck)
    {
        offCameraSince = 0;
        return;
    }
    if (!offCameraSince)
        offCameraSince = GetTickCount();
    else if (GetTickCount() - offCameraSince > 3000)
    {
        offCameraSince = 0;
        CAutoTest::Event("cutscene_unstuck", "\"name\":\"" + std::string(CCutsceneMgr::ms_cutsceneName, 0, 8) + "\"");
        CCutsceneMgr::ms_wasCutsceneSkipped = true;
        CCutsceneMgr::FinishCutscene();
    }
}

void CCutsceneCleanup::Process()
{
    ProcessProofs();
    ProcessStuckCutscene();

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

    // a scripted camera the mission left behind (failed while it ran, e.g. Supply Lines' RC plane camera): nobody
    // gives it back, the player is stuck with it and the next mission's cutscene camera could not take over (its
    // skip check never ran: 4-player sweep, New Model Army and Up, Up and Away! stuck in their opening cutscene)
    if (TheCamera.m_nWhoIsInControlOfTheCamera == 1 && !CCutsceneMgr::ms_running)  // 1 = script
    {
        CAutoTest::Event("script_camera_restored");
        TheCamera.Restore();
    }

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
