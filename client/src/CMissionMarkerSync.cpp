#include "stdafx.h"
#include "CMissionMarkerSync.h"
#include "COpCodeSync.h"
#include <CCheckpoints.h>

using MarkersPacket = Packets::Blips::MissionMarkers;

// host: the areas the mission drew recently (an area disappears 300 ms after the mission stops drawing it)
struct SSeenArea { MarkersPacket::Area area; uint32_t seenAt; };
static std::vector<SSeenArea> ms_seenAreas;
static MarkersPacket ms_lastSent{};
static uint32_t ms_nLastSendTime = 0;

// partners: the host's markers, dropped when no update came for 3 s (host left, mission over)
static MarkersPacket ms_received{};
static uint32_t ms_nReceivedAt = 0;

// mirrored markers get their own ids so they never replace one of the partner's own
static constexpr uint32_t MIRROR_ID_XOR = 0x5A000000;

static bool ShouldRecord()
{
    return CLocalPlayer::m_bIsHost && CNetwork::m_bAuthenticated && !CNetworkPlayerManager::m_pPlayers.empty() &&
           CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
}

static void __cdecl HighlightImportantArea_Hook(int id, float fromX, float fromY, float toX, float toY, float z)
{
    plugin::Call<0x485E00, int, float, float, float, float, float>(id, fromX, fromY, toX, toY, z);

    if (!ShouldRecord() || !COpCodeSync::IsCurrentScriptUnportedMission())
        return;

    MarkersPacket::Area area{id, fromX, fromY, toX, toY, z};
    uint32_t now = CTimer::m_snTimeInMilliseconds;
    for (SSeenArea& seen : ms_seenAreas)
    {
        if (seen.area.id == id)
        {
            seen.area = area;
            seen.seenAt = now;
            return;
        }
    }
    ms_seenAreas.push_back({area, now});
}

void CMissionMarkerSync::InjectHooks()
{
    // every call of CTheScripts::HighlightImportantArea: the locate commands with "show marker"
    for (uintptr_t site : {0x467989, 0x467A96, 0x467FA0, 0x46805E, 0x4801D7, 0x48704F, 0x4873A4, 0x4876B2, 0x4879B2,
             0x487CA9, 0x487F13, 0x488E6A, 0x489111, 0x489378})
    {
        patch::RedirectCall(site, HighlightImportantArea_Hook);
    }
}

static bool SameAsLastSent(const MarkersPacket& packet)
{
    if (packet.numAreas != ms_lastSent.numAreas || packet.numCheckpoints != ms_lastSent.numCheckpoints)
        return false;
    for (int i = 0; i < packet.numAreas; i++)
    {
        const MarkersPacket::Area &x = packet.areas[i], &y = ms_lastSent.areas[i];
        if (x.id != y.id || x.fromX != y.fromX || x.fromY != y.fromY || x.toX != y.toX || x.toY != y.toY || x.z != y.z)
            return false;
    }
    for (int i = 0; i < packet.numCheckpoints; i++)
    {
        const MarkersPacket::Checkpoint &x = packet.checkpoints[i], &y = ms_lastSent.checkpoints[i];
        if (x.id != y.id || x.type != y.type || (x.position - y.position).Magnitude() > 0.05f || x.size != y.size ||
            (x.direction - y.direction).Magnitude() > 0.05f || x.r != y.r || x.g != y.g || x.b != y.b || x.a != y.a)
            return false;
    }
    return true;
}

static void ProcessHost()
{
    uint32_t now = CTimer::m_snTimeInMilliseconds;
    ms_seenAreas.erase(std::remove_if(ms_seenAreas.begin(), ms_seenAreas.end(), [now](const SSeenArea& s) { return now - s.seenAt > 300; }), ms_seenAreas.end());

    uint32_t tick = GetTickCount();
    if (tick - ms_nLastSendTime < 200)
        return;

    MarkersPacket packet{};
    for (const SSeenArea& s : ms_seenAreas)
    {
        if (packet.numAreas < MarkersPacket::MAX_AREAS)
            packet.areas[packet.numAreas++] = s.area;
    }
    // script checkpoints (create_checkpoint) are placed once and stay until deleted: send the live list
    for (int i = 0; ShouldRecord() && i < 32 && packet.numCheckpoints < MarkersPacket::MAX_CHECKPOINTS; i++)
    {
        CCheckpoint& c = CCheckpoints::m_aCheckPtArray[i];
        if (!c.m_bIsUsed || ((uint32_t)c.m_nIdentifier & 0xFF000000) == MIRROR_ID_XOR)  // never echo mirrored ones
            continue;
        packet.checkpoints[packet.numCheckpoints++] = {c.m_nIdentifier, c.m_nType, c.m_vecPosition, c.m_vecDirection, c.m_fSize,
            c.m_colour.r, c.m_colour.g, c.m_colour.b, c.m_colour.a, (uint16_t)c.m_nPulsePeriod, c.m_fPulseFraction, c.m_nRotateRate};
    }

    // changes go out at once (max 5/s); an unchanged non-empty set is repeated every second as a keep-alive
    bool empty = packet.numAreas == 0 && packet.numCheckpoints == 0;
    bool same = SameAsLastSent(packet);
    if (same && (empty || tick - ms_nLastSendTime < 1000))
        return;

    GetPacketFactory().Send(packet);
    ms_lastSent = packet;
    ms_nLastSendTime = tick;
}

// script checkpoints stay until deleted (unlike 3D markers, which vanish when not placed for a frame): remove the
// mirrored ones the host no longer draws
static void DeleteCheckpointsNotIn(const MarkersPacket& from, const MarkersPacket* still)
{
    for (int i = 0; i < from.numCheckpoints; i++)
    {
        bool kept = false;
        for (int k = 0; still && k < still->numCheckpoints; k++)
            kept |= still->checkpoints[k].id == from.checkpoints[i].id;
        if (!kept)
            CCheckpoints::DeleteCP(from.checkpoints[i].id ^ MIRROR_ID_XOR, from.checkpoints[i].type);
    }
}

static void ProcessPartner()
{
    if (ms_nReceivedAt == 0)
        return;
    if (GetTickCount() - ms_nReceivedAt > 3000)
    {
        DeleteCheckpointsNotIn(ms_received, nullptr);
        ms_received = MarkersPacket{};
        ms_nReceivedAt = 0;
        return;
    }

    for (int i = 0; i < ms_received.numAreas; i++)
    {
        const MarkersPacket::Area& a = ms_received.areas[i];
        CTheScripts::HighlightImportantArea(a.id ^ MIRROR_ID_XOR, a.fromX, a.fromY, a.toX, a.toY, a.z);
    }
    for (int i = 0; i < ms_received.numCheckpoints; i++)
    {
        MarkersPacket::Checkpoint c = ms_received.checkpoints[i];
        CCheckpoints::PlaceMarker(c.id ^ MIRROR_ID_XOR, c.type, c.position, c.direction, c.size, c.r, c.g, c.b, c.a, c.pulsePeriod,
            c.pulseFraction, c.rotateRate);
    }
}

void CMissionMarkerSync::Process()
{
    if (!CNetwork::m_bAuthenticated)
        return;

    if (CLocalPlayer::m_bIsHost)
        ProcessHost();
    else
        ProcessPartner();
}

void CMissionMarkerSync::HandlePacket(const MarkersPacket& packet)
{
    DeleteCheckpointsNotIn(ms_received, &packet);
    ms_received = packet;
    ms_nReceivedAt = GetTickCount();
}

int CMissionMarkerSync::GetMirroredCount()
{
    if (CLocalPlayer::m_bIsHost)
        return ms_lastSent.numAreas + ms_lastSent.numCheckpoints;  // host: what it last sent
    if (ms_nReceivedAt == 0 || GetTickCount() - ms_nReceivedAt > 3000)
        return 0;
    return ms_received.numAreas + ms_received.numCheckpoints;
}
