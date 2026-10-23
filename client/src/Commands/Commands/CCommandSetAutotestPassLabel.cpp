#include "stdafx.h"
#include "CCommandSetAutotestPassLabel.h"
#include "CAutoTest.h"

// Coop.SetAutotestPassLabel(@label): for missions without Rockstar's debug skip, the autotest passmission command
// jumps the script to this label (its pass routine). Does nothing outside autotest.
void CCommandSetAutotestPassLabel::Process(CRunningScript* script)
{
    script->CollectParameters(1);
    CAutoTest::SetPassLabel(script, ScriptParams[0]);
}
