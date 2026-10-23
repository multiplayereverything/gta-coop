#pragma once
#include "../CCustomCommand.h"
class CCommandSetAutotestPassLabel :
    public CCustomCommand
{
    // Inherited via CCustomCommand
    void Process(CRunningScript* script) override;
};
