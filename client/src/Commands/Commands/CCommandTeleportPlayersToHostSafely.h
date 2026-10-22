#pragma once
#include "../CCustomCommand.h"
class CCommandTeleportPlayersToHostSafely :
    public CCustomCommand
{
    // Inherited via CCustomCommand
    void Process(CRunningScript* script) override;

public:
    // unported missions (no Coop.TeleportPlayersToHostSafely in their script): bring partners that are far away
    // next to the host after the mission moved the host. Requested from COpCodeSync, run once per frame from Main.cpp.
    static void RequestFarPartnersTeleport();
    static void ProcessPendingTeleport();
};

