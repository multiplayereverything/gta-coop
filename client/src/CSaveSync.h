#pragma once

// Saving in coop: whoever saves, the host's game saves that slot and sends the file to everyone, so all players
// have the same story/mission progress in that slot. Each player's own look (clothes, hair, tattoos, fat/muscle)
// is kept in a small file next to the save (GTASAsfN.b.coop) and put back on CJ when that save is loaded.
class CSaveSync
{
public:
    static void InjectHooks();
    static void Process();
    static void HandlePacket(const Packets::Blips::SaveFileChunk& packet);
    static void HandlePacket(const Packets::Blips::SaveRequest& packet);

    static void SaveFromCommand(int slot);  // autotest: what the save menu does
    static std::string SlotPath(int slot);  // full path of the save file of a slot (0-7)
    static bool ApplyLookForSlot(int slot);  // autotest: what loading that slot does to the look
};
