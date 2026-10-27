#pragma once
class WorldHooks
{
public: 
	static void InjectHooks();
	// sends a TagUpdate for every tag whose alpha went up since `before` (alphas of CTagManager::ms_tagDesc)
	static void SendChangedTags(const uint8_t* before);

	static std::unordered_map<CVehicle*, std::vector<void*>> m_aVehicleStackMap;
};

