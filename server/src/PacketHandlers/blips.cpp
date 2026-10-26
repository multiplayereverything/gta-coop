#include "network/packets/blips.h"
#include "network/packet_types.h"
#include "stdafx.h"

PACKET_HANDLER(ePacketType::UPDATE_CHECKPOINT, Packets::Blips::UpdateCheckpoint* pUpdateCheckpoint, CNetworkPlayer* pNetworkPlayer)
{
    if (pNetworkPlayer->m_bIsHost)
    {
        if (auto pTargetPlayer = CNetworkPlayerManager::GetPlayer(pUpdateCheckpoint->forWhoPlayerId))
        {
            GetPacketFactory().Send(*pUpdateCheckpoint, pTargetPlayer);
        }
    }
}

PACKET_HANDLER(ePacketType::REMOVE_CHECKPOINT, Packets::Blips::RemoveCheckpoint* pRemoveCheckpoint, CNetworkPlayer* pNetworkPlayer)
{
    if (pNetworkPlayer->m_bIsHost)
    {
        if (auto pTargetPlayer = CNetworkPlayerManager::GetPlayer(pRemoveCheckpoint->forWhoPlayerId))
        {
            GetPacketFactory().Send(*pRemoveCheckpoint, pTargetPlayer);
        }
    }
}

PACKET_HANDLER(ePacketType::MISSION_MARKERS, Packets::Blips::MissionMarkers* pMissionMarkers, CNetworkPlayer* pNetworkPlayer)
{
    if (pNetworkPlayer->m_bIsHost)
    {
        GetPacketFactory().SendToAll(*pMissionMarkers, pNetworkPlayer);
    }
}

PACKET_HANDLER(ePacketType::MISSION_PICKUPS, Packets::Blips::MissionPickups* pMissionPickups, CNetworkPlayer* pNetworkPlayer)
{
    if (pNetworkPlayer->m_bIsHost)
    {
        GetPacketFactory().SendToAll(*pMissionPickups, pNetworkPlayer);
    }
}

PACKET_HANDLER(ePacketType::MISSION_PICKUP_COLLECTED, Packets::Blips::MissionPickupCollected* pMissionPickupCollected, CNetworkPlayer* pNetworkPlayer)
{
    CNetworkPlayer* pHost = CNetworkPlayerManager::GetHost();
    if (pHost && pHost != pNetworkPlayer)
    {
        GetPacketFactory().Send(*pMissionPickupCollected, pHost);
    }
}

PACKET_HANDLER(ePacketType::MISSION_FIRES, Packets::Blips::MissionFires* pMissionFires, CNetworkPlayer* pNetworkPlayer)
{
    if (pNetworkPlayer->m_bIsHost)
    {
        GetPacketFactory().SendToAll(*pMissionFires, pNetworkPlayer);
    }
}

PACKET_HANDLER(ePacketType::MISSION_FIRE_OUT, Packets::Blips::MissionFireOut* pMissionFireOut, CNetworkPlayer* pNetworkPlayer)
{
    CNetworkPlayer* pHost = CNetworkPlayerManager::GetHost();
    if (pHost && pHost != pNetworkPlayer)
    {
        GetPacketFactory().Send(*pMissionFireOut, pHost);
    }
}

PACKET_HANDLER(ePacketType::MISSION_TRAINS, Packets::Blips::MissionTrains* pMissionTrains, CNetworkPlayer* pNetworkPlayer)
{
    if (pNetworkPlayer->m_bIsHost)
    {
        GetPacketFactory().SendToAll(*pMissionTrains, pNetworkPlayer);
    }
}

PACKET_HANDLER(ePacketType::SAVE_FILE_CHUNK, Packets::Blips::SaveFileChunk* pSaveFileChunk, CNetworkPlayer* pNetworkPlayer)
{
    if (pNetworkPlayer->m_bIsHost)
    {
        GetPacketFactory().SendToAll(*pSaveFileChunk, pNetworkPlayer);
    }
}

PACKET_HANDLER(ePacketType::SAVE_REQUEST, Packets::Blips::SaveRequest* pSaveRequest, CNetworkPlayer* pNetworkPlayer)
{
    CNetworkPlayer* pHost = CNetworkPlayerManager::GetHost();
    if (pHost && pHost != pNetworkPlayer)
    {
        GetPacketFactory().Send(*pSaveRequest, pHost);
    }
}

PACKET_HANDLER(ePacketType::USER_TRACK_LIST, Packets::Blips::UserTrackList* pUserTrackList, CNetworkPlayer* pNetworkPlayer)
{
    pUserTrackList->senderPlayerid = pNetworkPlayer->m_playerId;
    GetPacketFactory().SendToAll(*pUserTrackList, pNetworkPlayer);
}

PACKET_HANDLER(ePacketType::USER_TRACK_REQUEST, Packets::Blips::UserTrackRequest* pUserTrackRequest, CNetworkPlayer* pNetworkPlayer)
{
    pUserTrackRequest->senderPlayerid = pNetworkPlayer->m_playerId;
    if (auto pOwner = CNetworkPlayerManager::GetPlayer(pUserTrackRequest->owner))
    {
        GetPacketFactory().Send(*pUserTrackRequest, pOwner);
    }
}

PACKET_HANDLER(ePacketType::USER_TRACK_CHUNK, Packets::Blips::UserTrackChunk* pUserTrackChunk, CNetworkPlayer* pNetworkPlayer)
{
    pUserTrackChunk->senderPlayerid = pNetworkPlayer->m_playerId;
    if (auto pTarget = CNetworkPlayerManager::GetPlayer(pUserTrackChunk->to))
    {
        GetPacketFactory().Send(*pUserTrackChunk, pTarget);
    }
}

PACKET_HANDLER(ePacketType::GANG_ZONES, Packets::Blips::GangZones* pGangZones, CNetworkPlayer* pNetworkPlayer)
{
    if (pNetworkPlayer->m_bIsHost)
    {
        GetPacketFactory().SendToAll(*pGangZones, pNetworkPlayer);
    }
}

PACKET_HANDLER(ePacketType::COLLECTIBLE_COLLECTED, Packets::Blips::CollectibleCollected* pCollectibleCollected, CNetworkPlayer* pNetworkPlayer)
{
    pCollectibleCollected->senderPlayerid = pNetworkPlayer->m_playerId;
    GetPacketFactory().SendToAll(*pCollectibleCollected, pNetworkPlayer);
}
