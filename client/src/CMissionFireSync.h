#pragma once

// Fires a host-run mission starts at a spot (start_script_fire) burned only on the host: partners neither saw them
// nor got hurt by them. The host sends its mission fires, partners start copies; a partner putting one out puts
// the host's fire out too (missions that check is_script_fire_extinguished see it).
class CMissionFireSync
{
public:
    static void Process();
    static void HandlePacket(const Packets::Blips::MissionFires& packet);
    static void HandlePacket(const Packets::Blips::MissionFireOut& packet);

    static int GetCount();  // autotest: host = fires it sends, partner = copies burning
};
