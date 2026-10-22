#pragma once
class CPatch
{
public:
	static void TemporaryPatches();
	static void RevertTemporaryPatches();
	static void RevertTemporaryPatchesForHost();
	static void PatchFramerate();
	static void ApplyPatches();

	// plugin-sdk's gameProcessEvent lives on the CGame::Process call at 0x53E981. ASI mods loaded after us
	// (CLEO 4.4) redirect that call without chaining to us, which silently stops all per-frame coop code.
	static void RememberGameProcessHook();
	static void ReclaimGameProcessHook();
};

