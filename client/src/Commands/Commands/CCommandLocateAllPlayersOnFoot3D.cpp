#include "stdafx.h"
#include "CCommandLocateAllPlayersOnFoot3D.h"
#include "CMissionStartSync.h"
#include "CAutoTest.h"
#include <map>

// a partner on foot inside the marker box for 1 s (not just running through it): moves the host there, true
static bool TriggeredByPartner(const CVector& position, const CVector& radius)
{
	// per marker: a contact script checks several markers every frame
	static std::map<std::pair<int, int>, uint32_t> partnerInSince;

	CPlayerPed* host = FindPlayerPed(0);
	if (!host || host->m_fHealth <= 0.0f || CWorld::Players[0].m_nPlayerState != PLAYERSTATE_PLAYING ||
		CCutsceneMgr::ms_running || CPad::GetPad(0)->DisablePlayerControls)
		return false;

	CNetworkPlayer* inside = nullptr;
	for (auto networkPlayer : CNetworkPlayerManager::m_pPlayers)
	{
		CPlayerPed* ped = networkPlayer->m_pPed;
		if (!ped || !ped->m_matrix || ped->m_fHealth <= 0.0f || ped->m_nPedFlags.bInVehicle || networkPlayer->m_bConnectionLost)
			continue;
		CVector offset = ped->GetPosition() - position;
		if (fabs(offset.x) <= radius.x && fabs(offset.y) <= radius.y && fabs(offset.z) <= (std::max)(radius.z, 2.0f))
		{
			inside = networkPlayer;
			break;
		}
	}

	uint32_t now = CTimer::m_snTimeInMilliseconds;
	std::pair<int, int> key((int)position.x, (int)position.y);
	if (!inside)
	{
		partnerInSince.erase(key);
		return false;
	}
	auto it = partnerInSince.find(key);
	// a stale entry (the partner left while the marker wasn't checked) starts over
	if (it == partnerInSince.end() || now - it->second > 5000)
	{
		partnerInSince[key] = now;
		return false;
	}
	if (now - it->second < 1000)
		return false;
	partnerInSince.erase(key);

	// outside markers are in the main area; one indoors (z ~1000) is in the partner's area
	uint8_t area = position.z > 500.0f ? inside->m_pPed->m_nAreaCode : 0;
	CMissionStartSync::MoveLocalPlayer(position, area, true);
	CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}%s started the mission.", inside->GetName().c_str());
	CAutoTest::Event("marker_by_partner", "\"id\":" + std::to_string(inside->m_playerId.value()));
	return true;
}

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

	// any player can start it: a partner who stands in the marker for a second brings the host's game to it (the
	// mission runs there, at the host's position); the mission-start teleport then brings everyone else
	if (!result && TriggeredByPartner(*position, *radius))
	{
		result = Command<Commands::LOCATE_CHAR_ON_FOOT_3D>(
			CPools::GetPedRef(FindPlayerPed(0)),
			position->x, position->y, position->z,
			radius->x, radius->y, radius->z,
			false);
	}

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
