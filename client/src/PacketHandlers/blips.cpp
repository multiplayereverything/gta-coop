#include "network/packets/scripts.h"
#include "network/packet_types.h"
#include "stdafx.h"
#include <CNetworkCheckpoint.h>
#include "CMissionMarkerSync.h"
#include "CMissionPickupSync.h"
#include "CMissionFireSync.h"
#include "CMissionTrainSync.h"

PACKET_HANDLER(ePacketType::UPDATE_CHECKPOINT, Packets::Blips::UpdateCheckpoint* pUpdateCheckpoint)
{
	if (CLocalPlayer::m_bIsHost)
		return;

	CNetworkCheckpoint::Update(pUpdateCheckpoint->position, pUpdateCheckpoint->radius);
}

PACKET_HANDLER(ePacketType::REMOVE_CHECKPOINT, Packets::Blips::RemoveCheckpoint* pRemoveCheckpoint)
{
	if (CLocalPlayer::m_bIsHost)
		return;

	CNetworkCheckpoint::Remove();
}

PACKET_HANDLER(ePacketType::MISSION_MARKERS, Packets::Blips::MissionMarkers* pMissionMarkers)
{
	if (CLocalPlayer::m_bIsHost)
		return;

	CMissionMarkerSync::HandlePacket(*pMissionMarkers);
}

PACKET_HANDLER(ePacketType::MISSION_PICKUPS, Packets::Blips::MissionPickups* pMissionPickups)
{
	if (CLocalPlayer::m_bIsHost)
		return;

	CMissionPickupSync::HandlePacket(*pMissionPickups);
}

PACKET_HANDLER(ePacketType::MISSION_PICKUP_COLLECTED, Packets::Blips::MissionPickupCollected* pMissionPickupCollected)
{
	if (!CLocalPlayer::m_bIsHost)
		return;

	CMissionPickupSync::HandlePacket(*pMissionPickupCollected);
}

PACKET_HANDLER(ePacketType::MISSION_FIRES, Packets::Blips::MissionFires* pMissionFires)
{
	if (CLocalPlayer::m_bIsHost)
		return;

	CMissionFireSync::HandlePacket(*pMissionFires);
}

PACKET_HANDLER(ePacketType::MISSION_FIRE_OUT, Packets::Blips::MissionFireOut* pMissionFireOut)
{
	if (!CLocalPlayer::m_bIsHost)
		return;

	CMissionFireSync::HandlePacket(*pMissionFireOut);
}

PACKET_HANDLER(ePacketType::MISSION_TRAINS, Packets::Blips::MissionTrains* pMissionTrains)
{
	if (CLocalPlayer::m_bIsHost)
		return;

	CMissionTrainSync::HandlePacket(*pMissionTrains);
}
