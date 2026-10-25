#include "stdafx.h"
#include "CGangZoneSync.h"
#include "CAutoTest.h"
#include <CZoneInfo.h>

using ZonesPacket = Packets::Blips::GangZones;

static CZoneInfo* ZoneInfos() { return (CZoneInfo*)0xBA1DF0; }
static int ZoneCount() { return *(int16_t*)0xBA1DE8; }

static void Pack(ZonesPacket& packet)
{
    int count = ZoneCount();
    if (count <= 0 || count * ZonesPacket::BYTES_PER_ZONE > ZonesPacket::MAX_BYTES)
    {
        packet.count = 0;
        return;
    }
    packet.count = (uint16_t)count;
    uint8_t* out = packet.data;
    for (int i = 0; i < count; i++)
    {
        CZoneInfo& zone = ZoneInfos()[i];
        memcpy(out, zone.m_nGangDensity, 10);
        out[10] = zone.m_ZoneColor.r;
        out[11] = zone.m_ZoneColor.g;
        out[12] = zone.m_ZoneColor.b;
        out[13] = zone.m_ZoneColor.a;
        out[14] = (uint8_t)zone.m_nFlags;
        out += ZonesPacket::BYTES_PER_ZONE;
    }
}

void CGangZoneSync::Process()
{
    static uint32_t lastCheck = 0, lastSend = 0;
    static ZonesPacket packet{}, lastSent{};  // ~9 KB each: not on the stack
    if (!CLocalPlayer::m_bIsHost || !CNetwork::m_bAuthenticated || CNetworkPlayerManager::m_pPlayers.empty())
    {
        lastSent.count = 0;  // a new partner / new host gets everything again
        return;
    }
    uint32_t now = GetTickCount();
    if (now - lastCheck < 2000)
        return;
    lastCheck = now;

    Pack(packet);
    bool changed = packet.count != lastSent.count ||
                   memcmp(packet.data, lastSent.data, packet.count * ZonesPacket::BYTES_PER_ZONE) != 0;
    if (packet.count == 0 || (!changed && now - lastSend < 10000))
        return;
    GetPacketFactory().Send(packet);
    lastSent = packet;
    lastSend = now;
}

void CGangZoneSync::HandlePacket(const ZonesPacket& packet)
{
    // only the same zone table (same game data): anything else would put territories on the wrong zones
    if (packet.count == 0 || packet.count != ZoneCount())
    {
        CAutoTest::Event("gang_zones_ignored", "\"theirs\":" + std::to_string(packet.count) + ",\"ours\":" + std::to_string(ZoneCount()));
        return;
    }
    const uint8_t* in = packet.data;
    for (int i = 0; i < packet.count; i++)
    {
        CZoneInfo& zone = ZoneInfos()[i];
        memcpy(zone.m_nGangDensity, in, 10);
        zone.m_ZoneColor.r = in[10];
        zone.m_ZoneColor.g = in[11];
        zone.m_ZoneColor.b = in[12];
        zone.m_ZoneColor.a = in[13];
        zone.m_nFlags = (char)in[14];
        in += ZonesPacket::BYTES_PER_ZONE;
    }
}
