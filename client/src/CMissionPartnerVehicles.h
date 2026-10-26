#pragma once

// Host only. Missions put the host in a mission vehicle whose other seats are usually taken by story NPCs
// (Sweet, Smoke, Ryder...), so partners can't ride along. When that happens this spawns copies of the vehicle
// right behind it for the partners (network vehicles, friendly blip, chat note) and releases them after the mission.
// Cars, bikes and BMXs only (no aircraft, boats, trains).
class CMissionPartnerVehicles
{
public:
    static void Process();
    static bool IsExtraVehicle(CVehicle* vehicle);  // one of the copies spawned for partners (host)
};
