#pragma once
#include "../CCustomCommand.h"
class CCommandIsAnyNetworkPlayerInArea3D :
    public CCustomCommand
{
    // Inherited via CCustomCommand
    void Process(CRunningScript* script) override;
};
