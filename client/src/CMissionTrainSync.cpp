#include "stdafx.h"
#include "CMissionTrainSync.h"
#include <CTrain.h>
#include <CStreaming.h>
#include "CAutoTest.h"
#include <sstream>
#include <unordered_set>

using TrainsPacket = Packets::Blips::MissionTrains;

struct SHostTrain
{
    int id;
    TrainsPacket::Train spawn;
    CTrain* engine;  // registered reference: nulled when the game deletes the train
};
static std::vector<SHostTrain*> ms_hostTrains;
static int ms_nNextId = 1;
static uint32_t ms_nLastSendTime = 0;
static int ms_nLastSentCount = 0;

struct SCopy
{
    CTrain* engine;
    CVector hostPosition;
};
static std::unordered_map<int, SCopy*> ms_copies;
static uint32_t ms_nReceivedAt = 0;

static void __cdecl CreateMissionTrain_Hook(CVector posn, bool clockwise, unsigned int trainType, CTrain** outFirst, CTrain** outLast,
    int node, int track, bool isMission)
{
    CTrain::CreateMissionTrain(posn, clockwise, trainType, outFirst, outLast, node, track, isMission);

    if (!CLocalPlayer::m_bIsHost || !outFirst || !*outFirst || ms_hostTrains.size() >= 16)
        return;
    SHostTrain* train = new SHostTrain{ms_nNextId++, {}, CTrain::FindEngine(*outFirst)};
    train->spawn.type = (uint8_t)trainType;
    train->spawn.clockwise = clockwise;
    train->spawn.node = node;
    train->spawn.track = (int8_t)track;
    train->spawn.spawn = posn;
    train->engine->RegisterReference((CEntity**)&train->engine);
    ms_hostTrains.push_back(train);
}

void CMissionTrainSync::InjectHooks()
{
    patch::RedirectCall(0x497FE4, CreateMissionTrain_Hook);  // create_mission_train (06D8)
    patch::RedirectCall(0x6F7C2C, CreateMissionTrain_Hook);  // random trains (host only, partners have them off)
}

static void ProcessHost()
{
    for (auto it = ms_hostTrains.begin(); it != ms_hostTrains.end();)
    {
        if (!(*it)->engine)
        {
            delete *it;
            it = ms_hostTrains.erase(it);
        }
        else
            ++it;
    }

    uint32_t tick = GetTickCount();
    if (tick - ms_nLastSendTime < 200 || (ms_hostTrains.empty() && ms_nLastSentCount == 0))
        return;

    TrainsPacket packet{};
    for (SHostTrain* train : ms_hostTrains)
    {
        if (packet.count >= TrainsPacket::MAX_TRAINS)
            break;
        TrainsPacket::Train t = train->spawn;
        t.id = train->id;
        t.position = train->engine->GetPosition();
        t.speed = train->engine->m_fTrainSpeed;
        t.rail = train->engine->m_fCurrentRailDistance;
        t.trackNow = train->engine->m_nTrackId;
        t.nodeNow = train->engine->m_nNodeIndex;
        packet.trains[packet.count++] = t;
    }
    GetPacketFactory().Send(packet);
    ms_nLastSentCount = packet.count;
    ms_nLastSendTime = tick;
}

// the train models must be in memory before a train is built (missions request them first; the game crashed in
// CVehicleModelInfo::CreateInstance otherwise). Kept loaded once requested.
static bool EnsureTrainModels()
{
    static const int models[] = {449, 537, 538, 569, 570, 590};
    bool missing = false;
    for (int model : models)
    {
        if (CStreaming::ms_aInfoForModel[model].m_nLoadState != LOADSTATE_LOADED)
        {
            CStreaming::RequestModel(model, GAME_REQUIRED | KEEP_IN_MEMORY);
            missing = true;
        }
    }
    if (!missing)
        return true;
    CStreaming::LoadAllRequestedModels(false);
    for (int model : models)
    {
        if (CStreaming::ms_aInfoForModel[model].m_nLoadState != LOADSTATE_LOADED)
            return false;
    }
    return true;
}

static void RemoveCopy(SCopy* copy)
{
    if (copy->engine && copy->engine->IsVTableValid())
    {
        CTrain* engine = copy->engine;
        engine->CleanUpOldReference((CEntity**)&copy->engine);
        CTrain::RemoveOneMissionTrain(engine);
    }
    delete copy;
}

static void RemoveAllCopies()
{
    for (auto& [id, copy] : ms_copies)
        RemoveCopy(copy);
    ms_copies.clear();
}

void CMissionTrainSync::Process()
{
    if (!CNetwork::m_bAuthenticated)
        return;

    if (CLocalPlayer::m_bIsHost)
    {
        if (!ms_copies.empty())  // just became host: the old host's trains are not ours
            RemoveAllCopies();
        ProcessHost();
    }
    else
    {
        // a partner who was host before keeps no records of its own trains
        for (SHostTrain* train : ms_hostTrains)
        {
            if (train->engine)
                train->engine->CleanUpOldReference((CEntity**)&train->engine);
            delete train;
        }
        ms_hostTrains.clear();

        if (!ms_copies.empty() && GetTickCount() - ms_nReceivedAt > 6000)  // host gone or silent
            RemoveAllCopies();
    }
}

void CMissionTrainSync::HandlePacket(const TrainsPacket& packet)
{
    ms_nReceivedAt = GetTickCount();

    std::unordered_set<int> listed;
    for (int i = 0; i < packet.count; i++)
    {
        const TrainsPacket::Train& t = packet.trains[i];
        listed.insert(t.id);

        auto it = ms_copies.find(t.id);
        if (it != ms_copies.end() && !it->second->engine)  // deleted locally: create it again
        {
            delete it->second;
            ms_copies.erase(it);
            it = ms_copies.end();
        }
        if (it == ms_copies.end())
        {
            if (!EnsureTrainModels())
                continue;  // next update tries again
            CTrain *first = nullptr, *last = nullptr;
            // always a mission train here, so the partner's own train cleanup never removes it
            // on the host's track (left to itself the partner's game picked another track for the same spot)
            if (t.trackNow < 0 || t.trackNow > 3 || t.nodeNow < 0 || (unsigned)t.nodeNow >= NumTrackNodes[t.trackNow])
                continue;
            CTrain::CreateMissionTrain(t.position, t.clockwise, t.type, &first, &last, t.nodeNow, t.trackNow, true);
            if (!first)
                continue;
            SCopy* copy = new SCopy{CTrain::FindEngine(first), t.position};
            copy->engine->RegisterReference((CEntity**)&copy->engine);
            it = ms_copies.emplace(t.id, copy).first;
        }

        SCopy* copy = it->second;
        copy->hostPosition = t.position;
        if (copy->engine->m_nTrackId != t.trackNow)
        {
            CAutoTest::Event("train_track_mismatch", "\"copyTrack\":" + std::to_string((int)copy->engine->m_nTrackId) + ",\"hostTrack\":" + std::to_string((int)t.trackNow) + ",\"copyRail\":" + std::to_string(copy->engine->m_fCurrentRailDistance) + ",\"hostRail\":" + std::to_string(t.rail));
            RemoveCopy(copy);  // on another track: built again from the next update
            ms_copies.erase(it);
            continue;
        }
        // keep it where the host's train is: shift every carriage along the track by the engine's difference
        float delta = t.rail - copy->engine->m_fCurrentRailDistance;
        if (fabs(delta) > 4.0f)
        {
            for (CTrain* c = copy->engine; c; c = c->m_pNextCarriage)
                c->m_fCurrentRailDistance += delta;
            for (CTrain* c = copy->engine->m_pPrevCarriage; c; c = c->m_pPrevCarriage)
                c->m_fCurrentRailDistance += delta;
        }
        // mission trains slow down to their cruise speed: set both. They take script units (per second);
        // m_fTrainSpeed is per 50 fps frame
        CTrain::SetTrainSpeed(copy->engine, t.speed * 50.0f);
        CTrain::SetTrainCruiseSpeed(copy->engine, t.speed * 50.0f);
    }

    for (auto it = ms_copies.begin(); it != ms_copies.end();)
    {
        if (!listed.count(it->first))
        {
            RemoveCopy(it->second);  // gone on the host
            it = ms_copies.erase(it);
        }
        else
            ++it;
    }
}

int CMissionTrainSync::GetCount()
{
    return CLocalPlayer::m_bIsHost ? (int)ms_hostTrains.size() : (int)ms_copies.size();
}

float CMissionTrainSync::GetMaxOffset()
{
    float worst = 0.0f;
    for (auto& [id, copy] : ms_copies)
    {
        if (copy->engine)
            worst = (std::max)(worst, (copy->engine->GetPosition() - copy->hostPosition).Magnitude());
    }
    return worst;
}

std::string CMissionTrainSync::Describe()
{
    std::ostringstream out;
    out.setf(std::ios::fixed);
    out.precision(1);
    if (CLocalPlayer::m_bIsHost)
    {
        for (SHostTrain* t : ms_hostTrains)
            if (t->engine)
                out << "host#" << t->id << " type " << (int)t->spawn.type << " cw " << t->spawn.clockwise << " node " << t->spawn.node
                    << " track " << (int)t->spawn.track << " at " << t->engine->GetPosition().x << "," << t->engine->GetPosition().y
                    << " speed " << t->engine->m_fTrainSpeed << " trackNow " << (int)t->engine->m_nTrackId << " rail " << t->engine->m_fCurrentRailDistance << "; ";
    }
    else
    {
        for (auto& [id, c] : ms_copies)
            if (c->engine)
                out << "copy#" << id << " at " << c->engine->GetPosition().x << "," << c->engine->GetPosition().y << " host "
                    << c->hostPosition.x << "," << c->hostPosition.y << " speed " << c->engine->m_fTrainSpeed << "; ";
    }
    return out.str();
}
