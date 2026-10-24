#pragma once
#include "../CCustomCommand.h"

class CCommandCollectNetworkPlayersForTheMission : public CCustomCommand
{
	void Process(CRunningScript* script) override;

public:
	// a partner who respawns gets a new ped (new handle); the mission's $NETWORK_PLAYER[] globals still held the old
	// one, so that partner dropped out of the mission's objectives. Globals filled by this command are remembered
	// and switched to the new handle.
	static void OnNetworkPlayerPedReplaced(int oldRef, int newRef);
};
