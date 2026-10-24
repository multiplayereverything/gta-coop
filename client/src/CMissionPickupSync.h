#pragma once

// Pickups a mission creates (weapons, armour, objective items) existed only on the host, so partners could not see
// or collect them, and blips on them stayed hidden. The host sends its mission's pickups; partners create copies.
// A partner collecting a copy tells the host, which counts its own pickup as collected (the script sees it).
class CMissionPickupSync
{
public:
    static void Process();
    static void HandlePacket(const Packets::Blips::MissionPickups& packet);
    static void HandlePacket(const Packets::Blips::MissionPickupCollected& packet);

    static int GetCount();  // autotest: host = pickups it sends, partner = copies it has
};
