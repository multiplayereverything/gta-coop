#pragma once

class CCutsceneSkipVote
{
public:
    static void InjectHooks();

    // vote state as shown on screen ("Skip? (votes/voters)")
    static int GetVotes();
    static int GetVoters();
    static bool HasVoted();

    // acts like the local player pressing the skip button once (used by CAutoTest)
    static void PressSkip();
};
