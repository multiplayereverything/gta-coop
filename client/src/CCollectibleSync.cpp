#include "stdafx.h"
#include "CCollectibleSync.h"
#include "CAutoTest.h"
#include "UI/CChat.h"
#include <CPickups.h>
#include <CStats.h>
#include <unordered_map>

struct Kind
{
    uint16_t model;
    eStats stat;
    const char* name;
    int total;
};
static const Kind ms_kinds[] = {
    {953, STAT_OYSTERS_COLLECTED, "an oyster", 50},
    {954, STAT_HORSESHOES_COLLECTED, "a horseshoe", 50},
    {1253, STAT_SNAPSHOTS_TAKEN, "a snapshot", 50},
};

static const Kind* KindOf(int model)
{
    for (const Kind& k : ms_kinds)
        if (k.model == model)
            return &k;
    return nullptr;
}

static bool IsCollectible(const CPickup& p)
{
    return p.m_nPickupType != PICKUP_NONE && !p.m_nFlags.bDisabled && KindOf(p.m_nModelIndex);
}

static std::unordered_map<int, CVector> ms_seen;  // pickup index -> where, collectibles in the world at last check
static float ms_lastStat[3];
static bool ms_bHaveBaseline = false;

void CCollectibleSync::Process()
{
    static uint32_t lastCheck = 0;
    if (GetTickCount() - lastCheck < 250 || !FindPlayerPed(0))
        return;
    lastCheck = GetTickCount();

    std::unordered_map<int, CVector> now;
    for (int i = 0; i < MAX_NUM_PICKUPS; i++)
        if (IsCollectible(CPickups::aPickUps[i]))
            now[i] = CPickups::aPickUps[i].GetPosn();

    float stat[3];
    for (int k = 0; k < 3; k++)
        stat[k] = CStats::GetStatValue(ms_kinds[k].stat);

    // a find: that kind's stat went up by exactly the pickups of that kind that vanished since the last check
    // (a new game, a load or a script removing them changes the list without the stat, so nothing is sent)
    if (ms_bHaveBaseline)
    {
        for (int k = 0; k < 3; k++)
        {
            int gained = (int)(stat[k] - ms_lastStat[k] + 0.5f);
            if (gained <= 0)
                continue;
            std::vector<std::pair<int, CVector>> gone;
            for (auto& [index, pos] : ms_seen)
                if (!now.count(index) && CPickups::aPickUps[index].m_nModelIndex == ms_kinds[k].model)
                    gone.emplace_back(index, pos);
            if ((int)gone.size() != gained)
                continue;
            for (auto& [index, pos] : gone)
            {
                Packets::Blips::CollectibleCollected packet{};
                packet.model = ms_kinds[k].model;
                packet.position = pos;
                GetPacketFactory().Send(packet);
                CAutoTest::Event("collectible_sent", "\"model\":" + std::to_string(packet.model));
            }
        }
    }
    ms_seen = std::move(now);
    memcpy(ms_lastStat, stat, sizeof(stat));
    ms_bHaveBaseline = true;
}

void CCollectibleSync::HandlePacket(const Packets::Blips::CollectibleCollected& packet)
{
    const Kind* kind = KindOf(packet.model);
    if (!kind)
        return;
    for (int i = 0; i < MAX_NUM_PICKUPS; i++)
    {
        CPickup& p = CPickups::aPickUps[i];
        if (!IsCollectible(p) || p.m_nModelIndex != packet.model || (p.GetPosn() - packet.position).Magnitude() > 1.5f)
            continue;
        CPickups::RemovePickUp(CPickups::GetUniquePickupIndex(i));
        CStats::IncrementStat(kind->stat, 1.0f);
        // keep the next check from taking our own +1 for a find of ours
        for (int k = 0; k < 3; k++)
            ms_lastStat[k] = CStats::GetStatValue(ms_kinds[k].stat);
        ms_seen.erase(i);

        CNetworkPlayer* finder = CNetworkPlayerManager::GetPlayer(packet.senderPlayerid);
        CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}%s found %s (%d of %d).", finder ? finder->GetName().c_str() : "A player",
                          kind->name, (int)CStats::GetStatValue(kind->stat), kind->total);
        CAutoTest::Event("collectible_received", "\"model\":" + std::to_string(packet.model));
        return;
    }
    CAutoTest::Event("collectible_not_found", "\"model\":" + std::to_string(packet.model));
}
