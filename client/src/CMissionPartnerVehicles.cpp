#include "stdafx.h"
#include "CMissionPartnerVehicles.h"
#include "CAutoTest.h"

static constexpr int MAX_EXTRA_VEHICLES = 3;
static constexpr float PARTNER_RANGE = 200.0f;  // partners further away are not counted (they'll be teleported later)

struct SExtraVehicle
{
    int handle = -1;  // script handle, survives the vehicle being destroyed
    int blip = -1;
};

static std::vector<SExtraVehicle> ms_extraVehicles;
static CVehicle* ms_pServedVehicle = nullptr;  // the host's mission vehicle we already spawned extras for
static uint32_t ms_nLastCheck = 0;

static bool IsSupportedVehicle(CVehicle* vehicle)
{
    switch (vehicle->m_nVehicleSubType)  // eVehicleType
    {
        case VEHICLE_AUTOMOBILE:
        case VEHICLE_MTRUCK:
        case VEHICLE_QUAD:
        case VEHICLE_BIKE:
        case VEHICLE_BMX:
            return true;
        default:
            return false;
    }
}

static void Release()
{
    for (SExtraVehicle& extra : ms_extraVehicles)
    {
        if (extra.blip != -1)
            Command<Commands::REMOVE_BLIP>(extra.blip);
        if (CPools::GetVehicle(extra.handle))
            Command<Commands::MARK_CAR_AS_NO_LONGER_NEEDED>(extra.handle);
    }
    ms_extraVehicles.clear();
    ms_pServedVehicle = nullptr;
}

static void Announce(const char* text)
{
    CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}%s", text);

    Packets::System::ChatMessage packet{};
    MultiByteToWideChar(CP_UTF8, 0, text, -1, packet.message, Config::MAX_CHAT_MESSAGE_LENGTH);
    packet.message[Config::MAX_CHAT_MESSAGE_LENGTH] = L'\0';
    GetPacketFactory().Send(packet);
}

static void SpawnFor(CVehicle* vehicle, int count)
{
    int model = vehicle->m_nModelIndex;
    Command<Commands::REQUEST_MODEL>(model);
    Command<Commands::LOAD_ALL_MODELS_NOW>();

    CVector pos = vehicle->GetPosition();
    CVector forward = vehicle->m_matrix->up;  // SA matrices: `up` is the forward axis
    float headingDeg = vehicle->GetHeading() * 180.0f / PI;

    for (int i = 0; i < count; i++)
    {
        CVector spot = pos - forward * (7.0f * (i + 1));
        bool found = false;
        float ground = CWorld::FindGroundZFor3DCoord(spot.x, spot.y, spot.z + 3.0f, &found, nullptr);
        if (found)
            spot.z = ground + 1.0f;

        int handle = -1;
        Command<Commands::CREATE_CAR>(model, spot.x, spot.y, spot.z, &handle);
        if (handle == -1)
            continue;
        Command<Commands::SET_CAR_HEADING>(handle, headingDeg);

        SExtraVehicle extra{};
        extra.handle = handle;
        Command<Commands::ADD_BLIP_FOR_CAR>(handle, &extra.blip);
        Command<Commands::SET_BLIP_AS_FRIENDLY>(extra.blip, 1);
        Command<Commands::CHANGE_BLIP_COLOUR>(extra.blip, 1);  // green: friendly alone is blue, like the mission car itself
        ms_extraVehicles.push_back(extra);
    }
    Command<Commands::MARK_MODEL_AS_NO_LONGER_NEEDED>(model);

    char text[128];
    snprintf(text, sizeof text, "%d extra %s for partners behind the mission vehicle", count, count == 1 ? "vehicle" : "vehicles");
    Announce(text);
    CAutoTest::Event("partner_vehicles", "\"model\":" + std::to_string(model) + ",\"count\":" + std::to_string(count));
}

// the blue marker only shows partners where the spare car is; once someone sits in it, it's just in the way
static void UpdateBlips()
{
    for (SExtraVehicle& extra : ms_extraVehicles)
    {
        CVehicle* vehicle = CPools::GetVehicle(extra.handle);
        bool occupied = vehicle && (vehicle->m_pDriver || vehicle->m_nNumPassengers > 0);
        if ((occupied || !vehicle) && extra.blip != -1)
        {
            Command<Commands::REMOVE_BLIP>(extra.blip);
            extra.blip = -1;
        }
        else if (vehicle && !occupied && extra.blip == -1)
        {
            Command<Commands::ADD_BLIP_FOR_CAR>(extra.handle, &extra.blip);
            Command<Commands::SET_BLIP_AS_FRIENDLY>(extra.blip, 1);
            Command<Commands::CHANGE_BLIP_COLOUR>(extra.blip, 1);
        }
    }
}

void CMissionPartnerVehicles::Process()
{
    if (!CLocalPlayer::m_bIsHost)
        return;

    bool onMission = CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
    if (!onMission)
    {
        if (!ms_extraVehicles.empty() || ms_pServedVehicle)
            Release();
        return;
    }

    uint32_t now = GetTickCount();
    if (now - ms_nLastCheck < 1000)
        return;
    ms_nLastCheck = now;
    UpdateBlips();

    CPlayerPed* host = FindPlayerPed(0);
    if (!host || !host->m_nPedFlags.bInVehicle || CCutsceneMgr::ms_running)
        return;

    CVehicle* vehicle = host->m_pVehicle;
    if (!vehicle || vehicle == ms_pServedVehicle)
        return;

    static CVehicle* lastLogged = nullptr;
    if (vehicle != lastLogged)
    {
        lastLogged = vehicle;
        CAutoTest::Event("partner_vehicles_check",
            "\"model\":" + std::to_string(vehicle->m_nModelIndex) + ",\"createdBy\":" + std::to_string(vehicle->m_nCreatedBy) +
                ",\"type\":" + std::to_string(vehicle->m_nVehicleSubType) + ",\"seats\":" +
                std::to_string(vehicle->m_nMaxPassengers) + ",\"passengers\":" + std::to_string(vehicle->m_nNumPassengers) +
                ",\"hostDriver\":" + (vehicle->m_pDriver == host ? "true" : "false"));
    }

    if (vehicle->m_nCreatedBy != eVehicleCreatedBy::MISSION_VEHICLE || !IsSupportedVehicle(vehicle) ||
        ms_extraVehicles.size() >= MAX_EXTRA_VEHICLES)
        return;

    // partners near enough who are not riding in this vehicle already
    int partners = 0;
    for (CNetworkPlayer* networkPlayer : CNetworkPlayerManager::m_pPlayers)
    {
        CPed* ped = networkPlayer->m_pPed;
        if (ped && !(ped->m_nPedFlags.bInVehicle && ped->m_pVehicle == vehicle) &&
            (ped->GetPosition() - host->GetPosition()).Magnitude() < PARTNER_RANGE)
        {
            partners++;
        }
    }

    // re-checked every second while the host stays in: story NPCs usually get in after the host
    int freeSeats = vehicle->m_nMaxPassengers - vehicle->m_nNumPassengers;
    if (partners <= freeSeats)
        return;
    ms_pServedVehicle = vehicle;  // spawn once per vehicle

    int seatsPerVehicle = vehicle->m_nMaxPassengers + 1;
    int needed = (partners - freeSeats + seatsPerVehicle - 1) / seatsPerVehicle;
    needed = VMIN(needed, MAX_EXTRA_VEHICLES - (int)ms_extraVehicles.size());
    if (needed > 0)
        SpawnFor(vehicle, needed);
}

bool CMissionPartnerVehicles::IsExtraVehicle(CVehicle* vehicle)
{
    for (SExtraVehicle& extra : ms_extraVehicles)
        if (vehicle && CPools::GetVehicle(extra.handle) == vehicle)
            return true;
    return false;
}
