#include "stdafx.h"
#include "CMissionPickupSync.h"
#include "CAutoTest.h"
#include <CPickups.h>
#include <unordered_set>

using PickupsPacket = Packets::Blips::MissionPickups;

// host
static bool ms_bWasOnMission = false;
static std::unordered_set<int> ms_baseline;  // pickups that existed before the mission started
static PickupsPacket ms_lastSent{};
static uint32_t ms_nLastSendTime = 0;

// partners: host handle -> local copy
static std::unordered_map<int, int> ms_copies;
static std::unordered_set<int> ms_collected;  // host handles this partner collected (not recreated)
static uint32_t ms_nReceivedAt = 0;

// pickups a mission places; dropped weapons (ONCE_TIMEOUT) and money of dead peds are left alone
static bool IsMissionPickupType(unsigned char type)
{
    return type == PICKUP_ON_STREET || type == PICKUP_ONCE || type == PICKUP_ON_STREET_SLOW || type == PICKUP_ONCE_FOR_MISSION;
}

static bool IsOnMission()
{
    return CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
}

static void ProcessHost()
{
    bool onMission = IsOnMission();
    if (onMission && !ms_bWasOnMission)
    {
        ms_baseline.clear();
        for (int i = 0; i < MAX_NUM_PICKUPS; i++)
        {
            if (CPickups::aPickUps[i].m_nPickupType != PICKUP_NONE)
                ms_baseline.insert(CPickups::GetUniquePickupIndex(i));
        }
    }
    ms_bWasOnMission = onMission;

    uint32_t tick = GetTickCount();
    if (tick - ms_nLastSendTime < 250)
        return;

    PickupsPacket packet{};
    for (int i = 0; onMission && i < MAX_NUM_PICKUPS && packet.count < PickupsPacket::MAX_PICKUPS; i++)
    {
        CPickup& pickup = CPickups::aPickUps[i];
        if (!IsMissionPickupType(pickup.m_nPickupType) || pickup.m_nFlags.bDisabled)
            continue;
        int handle = CPickups::GetUniquePickupIndex(i);
        if (ms_baseline.count(handle))
            continue;
        packet.pickups[packet.count++] = {handle, (uint16_t)pickup.m_nModelIndex, pickup.m_nPickupType, pickup.GetPosn(), pickup.m_nAmmo};
    }

    bool same = packet.count == ms_lastSent.count;
    for (int i = 0; same && i < packet.count; i++)
    {
        same = packet.pickups[i].handle == ms_lastSent.pickups[i].handle &&
               (packet.pickups[i].position - ms_lastSent.pickups[i].position).Magnitude() < 0.5f;
    }
    // changes at once (max 4/s); a non-empty list is repeated every 2 s so partners know the host is still there
    if (same && (packet.count == 0 || tick - ms_nLastSendTime < 2000))
        return;

    GetPacketFactory().Send(packet);
    ms_lastSent = packet;
    ms_nLastSendTime = tick;
}

static void RemoveCopy(int localHandle)
{
    if (CPickups::GetActualPickupIndex(localHandle) != -1)
        CPickups::RemovePickUp(localHandle);
}

static void ProcessPartner()
{
    if (ms_copies.empty() && ms_collected.empty())
        return;

    // host gone or silent: drop the copies
    if (GetTickCount() - ms_nReceivedAt > 6000)
    {
        for (auto& [hostHandle, localHandle] : ms_copies)
            RemoveCopy(localHandle);
        ms_copies.clear();
        ms_collected.clear();
        return;
    }

    for (auto it = ms_copies.begin(); it != ms_copies.end();)
    {
        int localHandle = it->second;
        if (CPickups::IsPickUpPickedUp(localHandle) || CPickups::GetActualPickupIndex(localHandle) == -1)
        {
            Packets::Blips::MissionPickupCollected packet{};
            packet.handle = it->first;
            GetPacketFactory().Send(packet);
            CAutoTest::Event("mission_pickup_collected", "\"host\":" + std::to_string(it->first));
            ms_collected.insert(it->first);
            it = ms_copies.erase(it);
        }
        else
            ++it;
    }
}

void CMissionPickupSync::Process()
{
    if (!CNetwork::m_bAuthenticated)
        return;

    if (CLocalPlayer::m_bIsHost)
    {
        // just became host: copies from the old host are not ours to keep
        for (auto& [hostHandle, localHandle] : ms_copies)
            RemoveCopy(localHandle);
        ms_copies.clear();
        ms_collected.clear();
        ProcessHost();
    }
    else
    {
        ms_bWasOnMission = false;
        ProcessPartner();
    }
}

void CMissionPickupSync::HandlePacket(const PickupsPacket& packet)
{
    ms_nReceivedAt = GetTickCount();

    std::unordered_set<int> listed;
    for (int i = 0; i < packet.count; i++)
    {
        const PickupsPacket::Pickup& p = packet.pickups[i];
        listed.insert(p.handle);
        if (ms_copies.count(p.handle) || ms_collected.count(p.handle))
            continue;
        int local = CPickups::GenerateNewOne(p.position, p.model, p.type, p.ammo, 0, false, nullptr);
        if (local != -1)
            ms_copies[p.handle] = local;
    }

    for (auto it = ms_copies.begin(); it != ms_copies.end();)
    {
        if (!listed.count(it->first))
        {
            RemoveCopy(it->second);  // collected by the host or another player, or the mission removed it
            it = ms_copies.erase(it);
        }
        else
            ++it;
    }
    for (auto it = ms_collected.begin(); it != ms_collected.end();)
        it = listed.count(*it) ? std::next(it) : ms_collected.erase(it);
}

void CMissionPickupSync::HandlePacket(const Packets::Blips::MissionPickupCollected& packet)
{
    // the host's own pickup counts as collected (has_pickup_been_collected) and disappears for everyone
    int index = CPickups::GetActualPickupIndex(packet.handle);
    if (index == -1)
        return;
    CPickups::AddToCollectedPickupsArray(index);  // takes the array index and adds the reference bits itself
    CPickups::RemovePickUp(packet.handle);
    CAutoTest::Event("mission_pickup_taken_by_partner", "\"handle\":" + std::to_string(packet.handle));
}

int CMissionPickupSync::GetCount()
{
    return CLocalPlayer::m_bIsHost ? ms_lastSent.count : (int)ms_copies.size();
}
