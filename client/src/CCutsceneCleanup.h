#pragma once

// In single player nothing can end a mission while its cutscene plays. In coop a partner who dies (fire, a synced
// gunman) fails the host's mission through the death check, and the mission script jumps to its cleanup without
// clearing the cutscene: the cutscene stayed loaded and running on every game, and the next mission's cutscene
// crashed the camera (CCam::Process_FlyBy reading the old camera path, found by testing/soak-test.ps1).
// - a cutscene still loaded or running a moment after the mission ended is finished and cleared
// - while a cutscene runs the local player can't be hurt (no control, like single player), so this rarely happens
class CCutsceneCleanup
{
public:
    static void Process();
};
