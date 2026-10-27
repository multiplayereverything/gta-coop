#pragma once
class CNetworkPedManager
{
public:
	static std::vector<CNetworkPed*> m_pPeds;

	static inline uint32_t ms_nNextPedId = 1;
	// on-foot smoothing of peds synced from other players (autotest "smoothing 0" turns it off to compare)
	static inline bool ms_bSmoothing = true;
	// jitter metric for tests: mean change of a remote ped's per-frame movement (cm), and samples
	static inline double ms_fJitterSum = 0.0;
	static inline uint32_t ms_nJitterSamples = 0;
	static inline double ms_fOwnJitterSum = 0.0;  // same for the peds this game runs (baseline)
	static inline uint32_t ms_nOwnJitterSamples = 0;
	static inline float ms_fSmoothingStrength = 0.25f;  // share of the gap closed per 50 fps frame

	static CNetworkPed* GetPed(pedid_t pedid);
	static CNetworkPed* GetPed(CEntity* entity);
	static void Add(CNetworkPed* ped);
	static void Remove(CNetworkPed* ped);
	static void Update();
	static void Process();
	static void HideDuplicateShopkeeper(CNetworkPed* copy);
	static void AssignHost();
	static pedid_t AllocatePedId();
	static void ResetIdAllocator();
	static void RemoveHostedUnused();
};

