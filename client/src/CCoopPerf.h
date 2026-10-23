#pragma once
// Microseconds spent per frame in CoopAndreas' own per-frame code (autotest status "coopUs"), to see what to optimize
class CCoopPerf
{
public:
    enum { NET, PROCESS, DRAW, AUTOTEST, PEDS, VEHICLES, TAGS, CHAT, PLAYERLIST, CHECKPOINT, INPUT, VERSION, COUNT };
    static inline double ms_aTotalUs[COUNT] = {};
    static inline double ms_aLastUs[COUNT] = {};  // average per frame over the last second
    static inline int ms_nFrames = 0;
    static inline uint32_t ms_nLastReset = 0;

    struct Scope
    {
        int section;
        LARGE_INTEGER start;
        Scope(int s) : section(s) { QueryPerformanceCounter(&start); }
        ~Scope()
        {
            LARGE_INTEGER end, freq;
            QueryPerformanceCounter(&end);
            QueryPerformanceFrequency(&freq);
            ms_aTotalUs[section] += (end.QuadPart - start.QuadPart) * 1e6 / freq.QuadPart;
        }
    };

    static void EndFrame()
    {
        ms_nFrames++;
        uint32_t now = GetTickCount();
        if (now - ms_nLastReset < 1000)
            return;
        for (int i = 0; i < COUNT; i++)
        {
            ms_aLastUs[i] = ms_aTotalUs[i] / ms_nFrames;
            ms_aTotalUs[i] = 0;
        }
        ms_nFrames = 0;
        ms_nLastReset = now;
    }
};
