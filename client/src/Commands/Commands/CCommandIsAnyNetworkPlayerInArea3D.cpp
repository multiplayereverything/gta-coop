#include "stdafx.h"
#include "CCommandIsAnyNetworkPlayerInArea3D.h"
#include "../../CAutoTest.h"

// shops with one chair (barber, tattoo): a player only gets the chair blob while no other player is in it
void CCommandIsAnyNetworkPlayerInArea3D::Process(CRunningScript* script)
{
	script->CollectParameters(6);

	CVector* position = (CVector*)&ScriptParams[0];
	CVector* radius = (CVector*)&ScriptParams[3];
	bool result = false;
	for (auto networkPlayer : CNetworkPlayerManager::m_pPlayers)
	{
		CPlayerPed* ped = networkPlayer->m_pPed;
		if (!ped || !ped->m_matrix || ped->m_fHealth <= 0.0f || ped->m_nAreaCode != FindPlayerPed(0)->m_nAreaCode)
			continue;

		CVector offset = ped->GetPosition() - *position;
		if (fabs(offset.x) <= radius->x && fabs(offset.y) <= radius->y && fabs(offset.z) <= radius->z)
		{
			result = true;
			break;
		}
	}

	static int last = -1;
	if ((int)result != last)
	{
		last = result;
		CAutoTest::Event("chair_check", std::string("\"busy\":") + (result ? "true" : "false") + ",\"x\":" + std::to_string(position->x) + ",\"rx\":" + std::to_string(radius->x));
	}
	script->UpdateCompareFlag(result);
}
