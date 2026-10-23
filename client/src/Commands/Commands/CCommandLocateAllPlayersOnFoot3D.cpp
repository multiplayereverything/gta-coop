#include "stdafx.h"
#include "CCommandLocateAllPlayersOnFoot3D.h"

void CCommandLocateAllPlayersOnFoot3D::Process(CRunningScript* script)
{
	script->CollectParameters(7);

	if (!CLocalPlayer::m_bIsHost)
	{
		script->UpdateCompareFlag(false);
		return;
	}

	bool showMarker = ScriptParams[0] != 0;
	CVector* position = (CVector*)&ScriptParams[1];
	CVector* radius = (CVector*)&ScriptParams[4];

	bool result = Command<Commands::LOCATE_CHAR_ON_FOOT_3D>(
		CPools::GetPedRef(FindPlayerPed(0)),
		position->x, position->y, position->z,
		radius->x, radius->y, radius->z,
		showMarker);

	if (result)
	{
		// mission markers are ~1 m wide (Ryder's 1.2 m): three CJs could not all stand in one, so partners count
		// within 3.5 m. Partners who are far away (>50 m), dead or in another area don't block the start - the
		// mission-start teleport brings far partners to the host - so it works with however many are there.
		float partnerRadius = (std::max)(3.5f, (std::max)(radius->x, radius->y));
		for (auto networkPlayer : CNetworkPlayerManager::m_pPlayers)
		{
			CPlayerPed* ped = networkPlayer->m_pPed;
			if (!ped || !ped->m_matrix || ped->m_fHealth <= 0.0f || ped->m_nAreaCode != FindPlayerPed(0)->m_nAreaCode)
				continue;

			CVector offset = ped->GetPosition() - *position;
			float distance = CVector2D(offset.x, offset.y).Magnitude();
			if (distance > 50.0f)
				continue;

			if (distance > partnerRadius || fabs(offset.z) > (std::max)(radius->z, 3.0f) || ped->m_nPedFlags.bInVehicle)
			{
				result = false;
				break;
			}
		}
	}

	script->UpdateCompareFlag(result);
}
