#pragma once

// Every player is CJ, so during cutscenes and scripted widescreen scenes the other players' CJs stood around
// in the scene. Hides the remote player peds while a cutscene/widescreen scene runs (same rule as the name
// tags in CNetworkPlayerNameTag) and makes them visible again afterwards. Runs on every client.
class CCutscenePlayerHider
{
public:
    static void Process();
    static int GetHiddenCount();
};
