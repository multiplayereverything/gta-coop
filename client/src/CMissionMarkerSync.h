#pragma once

// Host-run (unported) missions draw their "go here" areas and race checkpoints only on the host. The host records
// what those missions draw and sends it to the partners, who draw the same markers.
class CMissionMarkerSync
{
public:
    static void InjectHooks();
    static void Process();  // drawing phase: host sends changes, partners draw the host's markers
    static void HandlePacket(const Packets::Blips::MissionMarkers& packet);

    static int GetMirroredCount();  // autotest: host = markers it sends, partner = host markers it draws
};
