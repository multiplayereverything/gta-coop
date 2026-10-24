#include "stdafx.h"
#include "CCommandCollectNetworkPlayersForTheMission.h"
#include "../../CAutoTest.h"

static int* ms_apStoredGlobals[3] = {};

void CCommandCollectNetworkPlayersForTheMission::Process(CRunningScript* script)
{
	uint8_t i = 0;

	memset(ScriptParams, 0, 3 * sizeof(int));

	for (auto networkPlayer : CNetworkPlayerManager::m_pPlayers)
	{
		if (auto player = networkPlayer->m_pPed)
		{
			ScriptParams[i] = CPools::GetPedRef(networkPlayer->m_pPed);
		}

		if (++i >= 3)
			break;
	}

	// where the handles go: plain global variables (type 2 + uint16 byte offset) are remembered, anything else
	// (locals, arrays with a variable index) is just stored as before
	uint8_t* ip = script->m_pCurrentIP;
	for (int k = 0; k < 3; k++)
	{
		ms_apStoredGlobals[k] = nullptr;
		if (ip[0] != 2)
			break;
		ms_apStoredGlobals[k] = (int*)(CTheScripts::ScriptSpace + *(uint16_t*)(ip + 1));
		ip += 3;
	}

	//CChat::AddMessage("CCommandCollectNetworkPlayersForTheMission::Process stored params %d %d %d", ScriptParams[0], ScriptParams[1], ScriptParams[2]);
	script->StoreParameters(3);
}

void CCommandCollectNetworkPlayersForTheMission::OnNetworkPlayerPedReplaced(int oldRef, int newRef)
{
	if (!CLocalPlayer::m_bIsHost || oldRef == 0 || oldRef == -1)
		return;

	for (int* global : ms_apStoredGlobals)
	{
		if (global && *global == oldRef)
		{
			*global = newRef;
			CAutoTest::Event("mission_partner_handle_updated", "\"old\":" + std::to_string(oldRef) + ",\"new\":" + std::to_string(newRef));
		}
	}
}
