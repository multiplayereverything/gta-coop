#pragma once

// The host's mission scripts broadcast set_area_visible (04BB) to every player, but each partner is moved
// in/out of an interior by separate synced commands. A partner who missed the move (in a car, arrived late) stood
// outside with an interior area visible (white sky, missing world), or inside with the outside visible.
// Outside a cutscene/scripted scene, keep the visible area matching where the local player really is.
// Runs on every client.
class CAreaConsistency
{
public:
    static void Process();
};
