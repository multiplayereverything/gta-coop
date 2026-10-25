#pragma once

// User tracks (custom songs in Documents\GTA San Andreas User Files\User Tracks) were only on the player who added
// them. Every player now tells the others which songs it has; a player missing one downloads it from its owner,
// one song at a time and throttled so the game's own traffic keeps flowing. Existing files are never overwritten.
// New songs play after the game scans them (Options > Audio Setup > User Track Options > Scan, or the next start).
class CUserTrackSync
{
public:
    static void Process();
    static void HandlePacket(const Packets::Blips::UserTrackList& packet);
    static void HandlePacket(const Packets::Blips::UserTrackRequest& packet);
    static void HandlePacket(const Packets::Blips::UserTrackChunk& packet);

    static std::string Folder();  // ...\GTA San Andreas User Files\User Tracks of this game
    static int GetReceivedCount();
};
