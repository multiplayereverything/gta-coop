#include "stdafx.h"
#include "CMissionFireSync.h"
#include "CAutoTest.h"
#include <CFireManager.h>
#include <unordered_set>

using FiresPacket = Packets::Blips::MissionFires;

// host
static FiresPacket ms_lastSent{};
static uint32_t ms_nLastSendTime = 0;

// partners: host fire id -> local script fire handle
static std::unordered_map<int, int> ms_copies;
static std::unordered_set<int> ms_putOut;  // host fires this partner put out (not restarted)
static uint32_t ms_nReceivedAt = 0;

static int FireId(int index) { return index | (gFireManager.m_aFires[index].m_nScriptReferenceIndex << 16); }

static void ProcessHost()
{
    uint32_t tick = GetTickCount();
    if (tick - ms_nLastSendTime < 250)
        return;

    bool onMission = CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
    FiresPacket packet{};
    for (int i = 0; onMission && i < MAX_NUM_FIRES && packet.count < FiresPacket::MAX_FIRES; i++)
    {
        CFire& fire = gFireManager.m_aFires[i];
        // fires on a spot only: burning cars/peds follow their entity, which every player already has
        if (!fire.m_nFlags.bActive || !fire.m_nFlags.bCreatedByScript || fire.m_pEntityTarget)
            continue;
        packet.fires[packet.count++] = {FireId(i), fire.m_vecPosition, (uint8_t)(std::clamp)(fire.m_fStrength, 1.0f, 255.0f),
            fire.m_nNumGenerationsAllowed};
    }

    bool same = packet.count == ms_lastSent.count;
    for (int i = 0; same && i < packet.count; i++)
        same = packet.fires[i].id == ms_lastSent.fires[i].id;
    // changes at once (max 4/s); a non-empty list is repeated every 2 s so partners know the host is still there
    if (same && (packet.count == 0 || tick - ms_nLastSendTime < 2000))
        return;

    GetPacketFactory().Send(packet);
    ms_lastSent = packet;
    ms_nLastSendTime = tick;
}

// StartScriptFire returns a script handle (array index | reference << 16); the fire manager works with the index
static bool IsCopyBurning(int localHandle)
{
    int index = localHandle & 0xFFFF;
    if (index >= MAX_NUM_FIRES)
        return false;
    CFire& fire = gFireManager.m_aFires[index];
    return fire.m_nFlags.bActive && fire.m_nScriptReferenceIndex == (short)(localHandle >> 16);
}

static void RemoveCopy(int localHandle)
{
    if (IsCopyBurning(localHandle))
        gFireManager.RemoveScriptFire((short)(localHandle & 0xFFFF));
}

static void ProcessPartner()
{
    if (ms_copies.empty() && ms_putOut.empty())
        return;

    if (GetTickCount() - ms_nReceivedAt > 6000)  // host gone or silent: put the copies out
    {
        for (auto& [id, local] : ms_copies)
            RemoveCopy(local);
        ms_copies.clear();
        ms_putOut.clear();
        return;
    }

    for (auto it = ms_copies.begin(); it != ms_copies.end();)
    {
        if (!IsCopyBurning(it->second))
        {
            Packets::Blips::MissionFireOut packet{};
            packet.id = it->first;
            GetPacketFactory().Send(packet);
            CAutoTest::Event("mission_fire_put_out", "\"host\":" + std::to_string(it->first));
            int index = it->second & 0xFFFF;  // free our script fire slot, unless it was given to another fire
            if (index < MAX_NUM_FIRES && gFireManager.m_aFires[index].m_nFlags.bCreatedByScript &&
                gFireManager.m_aFires[index].m_nScriptReferenceIndex == (short)(it->second >> 16))
                gFireManager.RemoveScriptFire((short)index);
            ms_putOut.insert(it->first);
            it = ms_copies.erase(it);
        }
        else
            ++it;
    }
}

void CMissionFireSync::Process()
{
    if (!CNetwork::m_bAuthenticated)
        return;

    if (CLocalPlayer::m_bIsHost)
    {
        for (auto& [id, local] : ms_copies)  // just became host: the old host's fires are not ours
            RemoveCopy(local);
        ms_copies.clear();
        ms_putOut.clear();
        ProcessHost();
    }
    else
        ProcessPartner();
}

void CMissionFireSync::HandlePacket(const FiresPacket& packet)
{
    ms_nReceivedAt = GetTickCount();

    std::unordered_set<int> listed;
    for (int i = 0; i < packet.count; i++)
    {
        const FiresPacket::Fire& f = packet.fires[i];
        listed.insert(f.id);
        if (ms_copies.count(f.id) || ms_putOut.count(f.id))
            continue;
        int local = gFireManager.StartScriptFire(f.position, nullptr, 0.0f, 0, f.generations, f.strength);
        if (local != -1)
            ms_copies[f.id] = local;
    }

    for (auto it = ms_copies.begin(); it != ms_copies.end();)
    {
        if (!listed.count(it->first))
        {
            RemoveCopy(it->second);  // out on the host (put out, burned down or removed by the mission)
            it = ms_copies.erase(it);
        }
        else
            ++it;
    }
    for (auto it = ms_putOut.begin(); it != ms_putOut.end();)
        it = listed.count(*it) ? std::next(it) : ms_putOut.erase(it);
}

void CMissionFireSync::HandlePacket(const Packets::Blips::MissionFireOut& packet)
{
    int index = packet.id & 0xFFFF;
    if (index >= MAX_NUM_FIRES)
        return;
    CFire& fire = gFireManager.m_aFires[index];
    if (!fire.m_nFlags.bActive || FireId(index) != packet.id)
        return;
    fire.Extinguish();
    CAutoTest::Event("mission_fire_out_by_partner", "\"id\":" + std::to_string(packet.id));
}

int CMissionFireSync::GetCount()
{
    return CLocalPlayer::m_bIsHost ? ms_lastSent.count : (int)ms_copies.size();
}
