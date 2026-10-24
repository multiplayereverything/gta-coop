#pragma once

// Trains are not network vehicles and partners have random trains switched off, so trains only existed on the
// host: partners could not see the train a mission is about (and could be hit by one they could not see). The host
// records every train it creates (mission and random) and sends where each engine is and how fast it goes;
// partners create the same train on the same track and keep it in step.
class CMissionTrainSync
{
public:
    static void InjectHooks();
    static void Process();
    static void HandlePacket(const Packets::Blips::MissionTrains& packet);

    static int GetCount();  // autotest: host = trains it sends, partner = copies running
    static float GetMaxOffset();  // autotest, partner: largest distance between a copy and the host's train
    static std::string Describe();  // autotest: where the trains are
};
