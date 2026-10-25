#pragma once

// Gang territories (which gang holds a zone, how strong, its colour on the map) lived in each player's own game:
// partners saw their own fresh-game map and gang presence instead of the host's. The host sends the zone data
// (CTheZones::ZoneInfoArray at 0xBA1DF0, 17 bytes per zone, count at 0xBA1DE8 - checked against GetZoneInfo)
// when it changes; partners copy it in.
class CGangZoneSync
{
public:
    static void Process();
    static void HandlePacket(const Packets::Blips::GangZones& packet);
};
