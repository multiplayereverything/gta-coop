#pragma once
class VehicleHooks
{
public:
	static void InjectHooks();
};

// how often a vehicle destructor returned with a clobbered ESI (repaired by the shim, see VehicleHooks.cpp)
extern volatile long g_nVehicleDtorEsiClobbered;
