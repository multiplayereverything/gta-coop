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
