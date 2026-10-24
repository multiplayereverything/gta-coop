#pragma once
class CNetworkVehicleManager
{
public:
    static inline std::vector<CNetworkVehicle*> m_pVehicles;

    static inline uint32_t ms_nNextVehicleId = 1;

    static CNetworkVehicle* GetVehicle(vehicleid_t vehicleid);
    static CNetworkVehicle* GetVehicle(CEntity* vehicle);
    static void Add(CNetworkVehicle* vehicle);
    static void Remove(CNetworkVehicle* vehicle);
    static void UpdateDriver(CVehicle* pVehicle);
    static void UpdateIdle();
    static void UpdatePassenger(CVehicle* pVehicle, CPlayerPed* pPlayerPed);
    static vehicleid_t AllocateVehicleId();
    static void ResetIdAllocator();
    static void RemoveHostedUnused();
    static void UpdateDamageSync();

    // cars driven by other players glide to the predicted synced position instead of jumping to every update
    static inline bool ms_bSmoothing = true;
    static inline float ms_fSmoothingStrength = 0.25f;  // share of the gap closed per 50 fps frame
    static constexpr float SNAP_DISTANCE = 6.0f;
    // autotest metric: moving frames in which a smoothed car steps backwards (a visible jump back)
    static inline int ms_nJitterSamples = 0;
    static inline int ms_nJitterBackSteps = 0;
    static inline int ms_nSnaps = 0;
    static void ProcessSmoothing();
};

