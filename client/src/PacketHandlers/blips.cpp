#include "network/packets/scripts.h"
#include "network/packet_types.h"
#include "stdafx.h"
#include <CNetworkCheckpoint.h>
#include "CMissionMarkerSync.h"
#include "CMissionPickupSync.h"
#include "CMissionFireSync.h"
#include "CMissionTrainSync.h"
#include "CSaveSync.h"
#include "CUserTrackSync.h"
#include "CCollectibleSync.h"
#include "CAutoTest.h"
#include "CMissionStartSync.h"
#include "CChatCommands.h"
#include "CGangZoneSync.h"

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

PACKET_HANDLER(ePacketType::SAVE_FILE_CHUNK, Packets::Blips::SaveFileChunk* pSaveFileChunk)
{
	if (CLocalPlayer::m_bIsHost)
		return;

	CSaveSync::HandlePacket(*pSaveFileChunk);
}

PACKET_HANDLER(ePacketType::SAVE_REQUEST, Packets::Blips::SaveRequest* pSaveRequest)
{
	if (!CLocalPlayer::m_bIsHost)
		return;

	CSaveSync::HandlePacket(*pSaveRequest);
}

PACKET_HANDLER(ePacketType::USER_TRACK_LIST, Packets::Blips::UserTrackList* pUserTrackList)
{
	CUserTrackSync::HandlePacket(*pUserTrackList);
}

PACKET_HANDLER(ePacketType::USER_TRACK_REQUEST, Packets::Blips::UserTrackRequest* pUserTrackRequest)
{
	CUserTrackSync::HandlePacket(*pUserTrackRequest);
}

PACKET_HANDLER(ePacketType::USER_TRACK_CHUNK, Packets::Blips::UserTrackChunk* pUserTrackChunk)
{
	CUserTrackSync::HandlePacket(*pUserTrackChunk);
}

PACKET_HANDLER(ePacketType::GANG_ZONES, Packets::Blips::GangZones* pGangZones)
{
	if (CLocalPlayer::m_bIsHost)
		return;

	CGangZoneSync::HandlePacket(*pGangZones);
}

PACKET_HANDLER(ePacketType::COLLECTIBLE_COLLECTED, Packets::Blips::CollectibleCollected* pCollectibleCollected)
{
	CCollectibleSync::HandlePacket(*pCollectibleCollected);
}

PACKET_HANDLER(ePacketType::PLAYER_CONNECTION_STATE, Packets::Blips::PlayerConnectionState* pPlayerConnectionState)
{
	if (CNetworkPlayer* pNetworkPlayer = CNetworkPlayerManager::GetPlayer(pPlayerConnectionState->player))
	{
		pNetworkPlayer->m_bConnectionLost = pPlayerConnectionState->lost;
		CAutoTest::Event(pPlayerConnectionState->lost ? "player_connection_lost" : "player_connection_back",
			"\"id\":" + std::to_string(pNetworkPlayer->m_playerId.value()));
	}
}

PACKET_HANDLER(ePacketType::MISSION_START_REQUEST, Packets::Blips::MissionStartRequest* pMissionStartRequest)
{
	CMissionStartSync::HandleRequest(*pMissionStartRequest);
}

PACKET_HANDLER(ePacketType::TELEPORT_PLAYER_REQUEST, Packets::Blips::TeleportPlayerRequest* pTeleportPlayerRequest)
{
	CChatCommands::HandleTeleportRequest(*pTeleportPlayerRequest);
}
