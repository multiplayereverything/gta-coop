#pragma once

// Oysters, horseshoes and snapshots are in every player's own world (INITIAL creates them) and only counted by the
// game that collected them, so a friend's finds were lost for the shared story (the host's save). When one is
// collected here - its pickup vanished and the matching stat went up in the same check - everyone else removes
// their copy (same model within 1.5 m) and adds the same stat, so the COLLS rewards count everyone's finds.
class CCollectibleSync
{
public:
    static void Process();
    static void HandlePacket(const Packets::Blips::CollectibleCollected& packet);
};
