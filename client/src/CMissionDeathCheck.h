#pragma once

// The mission death check (CRunningScript::DoDeatharrestCheck hook in PlayerHooks) fails the mission when another
// player is dead or arrested. One still lying dead from before failed the next mission at once: other players
// count only once seen alive during this mission. Updated every frame (the check itself only runs while the
// mission script is awake).
class CMissionDeathCheck
{
public:
    static void Process();
    static bool WasAliveThisMission(CPed* ped);
};
