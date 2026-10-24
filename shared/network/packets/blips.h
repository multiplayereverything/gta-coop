#pragma once

#include <CRadar.h>

namespace Packets::Blips
{
class UpdateCheckpoint : public Packet
{
    DEFINE_PACKET_TYPE(UpdateCheckpoint, ePacketType::UPDATE_CHECKPOINT, ePacketChannel::EVENT);

public:
    playerid_t forWhoPlayerId{}; // TODO(v0.3.1-alpha): send C2S only
    WorldPositionCompressed position{};
    WorldPositionCompressed radius{};

private:
    template <typename Stream>
    bool Serialize(Stream& stream)
    {
        serialize_playerid(stream, forWhoPlayerId);
        serialize_object(stream, position);
        serialize_object(stream, radius);
        return true;
    }
};

class RemoveCheckpoint : public Packet
{
    DEFINE_PACKET_TYPE(RemoveCheckpoint, ePacketType::REMOVE_CHECKPOINT, ePacketChannel::EVENT);

public:
    playerid_t forWhoPlayerId{}; // TODO(v0.3.1-alpha): send C2S only

private:
    template <typename Stream>
    bool Serialize(Stream& stream)
    {
        serialize_playerid(stream, forWhoPlayerId);
        return true;
    }
};
// what the host's host-run (unported) mission draws this moment: "go here" areas of locate commands and race
// checkpoints, so partners see the same markers (sent when it changes, at most 5 times a second)
class MissionMarkers : public Packet
{
    DEFINE_PACKET_TYPE(MissionMarkers, ePacketType::MISSION_MARKERS, ePacketChannel::SCRIPT);

public:
    static constexpr int MAX_AREAS = 8;
    static constexpr int MAX_CHECKPOINTS = 8;

    struct Area
    {
        int32_t id = 0;
        float fromX = 0, fromY = 0, toX = 0, toY = 0, z = 0;
    };
    struct Checkpoint
    {
        int32_t id = 0;
        uint16_t type = 0;
        CVector position{}, direction{};
        float size = 0;
        uint8_t r = 0, g = 0, b = 0, a = 0;
        uint16_t pulsePeriod = 0;
        float pulseFraction = 0;
        int16_t rotateRate = 0;
    };

    uint8_t numAreas = 0;
    Area areas[MAX_AREAS]{};
    uint8_t numCheckpoints = 0;
    Checkpoint checkpoints[MAX_CHECKPOINTS]{};

private:
    template <typename Stream>
    bool Serialize(Stream& stream)
    {
        serialize_int(stream, numAreas, 0, MAX_AREAS);
        for (int i = 0; i < numAreas; i++)
        {
            serialize_bits(stream, areas[i].id, 32);
            serialize_float(stream, areas[i].fromX);
            serialize_float(stream, areas[i].fromY);
            serialize_float(stream, areas[i].toX);
            serialize_float(stream, areas[i].toY);
            serialize_float(stream, areas[i].z);
        }
        serialize_int(stream, numCheckpoints, 0, MAX_CHECKPOINTS);
        for (int i = 0; i < numCheckpoints; i++)
        {
            Checkpoint& c = checkpoints[i];
            serialize_bits(stream, c.id, 32);
            serialize_bits(stream, c.type, 16);
            serialize_vector(stream, c.position);
            serialize_vector(stream, c.direction);
            serialize_float(stream, c.size);
            serialize_bits(stream, c.r, 8);
            serialize_bits(stream, c.g, 8);
            serialize_bits(stream, c.b, 8);
            serialize_bits(stream, c.a, 8);
            serialize_bits(stream, c.pulsePeriod, 16);
            serialize_float(stream, c.pulseFraction);
            serialize_bits(stream, c.rotateRate, 16);
        }
        return true;
    }
};
// pickups the host's current mission created (host -> partners, sent when the list changes)
class MissionPickups : public Packet
{
    DEFINE_PACKET_TYPE(MissionPickups, ePacketType::MISSION_PICKUPS, ePacketChannel::SCRIPT);

public:
    static constexpr int MAX_PICKUPS = 16;

    struct Pickup
    {
        int32_t handle = 0;  // the host's pickup handle
        uint16_t model = 0;
        uint8_t type = 0;
        CVector position{};
        uint32_t ammo = 0;
    };

    uint8_t count = 0;
    Pickup pickups[MAX_PICKUPS]{};

private:
    template <typename Stream>
    bool Serialize(Stream& stream)
    {
        serialize_int(stream, count, 0, MAX_PICKUPS);
        for (int i = 0; i < count; i++)
        {
            serialize_bits(stream, pickups[i].handle, 32);
            serialize_bits(stream, pickups[i].model, 16);
            serialize_bits(stream, pickups[i].type, 8);
            serialize_vector(stream, pickups[i].position);
            serialize_bits(stream, pickups[i].ammo, 32);
        }
        return true;
    }
};

// a partner collected its copy of a mission pickup (partner -> host): the host counts it as collected
class MissionPickupCollected : public Packet
{
    DEFINE_PACKET_TYPE(MissionPickupCollected, ePacketType::MISSION_PICKUP_COLLECTED, ePacketChannel::SCRIPT);

public:
    int32_t handle = 0;

private:
    template <typename Stream>
    bool Serialize(Stream& stream)
    {
        serialize_bits(stream, handle, 32);
        return true;
    }
};
// fires the host's current mission started at a spot (host -> partners, sent when the list changes)
class MissionFires : public Packet
{
    DEFINE_PACKET_TYPE(MissionFires, ePacketType::MISSION_FIRES, ePacketChannel::SCRIPT);

public:
    static constexpr int MAX_FIRES = 16;

    struct Fire
    {
        int32_t id = 0;  // the host's fire: array index | script reference << 16
        CVector position{};
        uint8_t strength = 0;
        int8_t generations = 0;
    };

    uint8_t count = 0;
    Fire fires[MAX_FIRES]{};

private:
    template <typename Stream>
    bool Serialize(Stream& stream)
    {
        serialize_int(stream, count, 0, MAX_FIRES);
        for (int i = 0; i < count; i++)
        {
            serialize_bits(stream, fires[i].id, 32);
            serialize_vector(stream, fires[i].position);
            serialize_bits(stream, fires[i].strength, 8);
            serialize_bits(stream, fires[i].generations, 8);
        }
        return true;
    }
};

// a partner put out its copy of a mission fire (partner -> host): the host's fire goes out too
class MissionFireOut : public Packet
{
    DEFINE_PACKET_TYPE(MissionFireOut, ePacketType::MISSION_FIRE_OUT, ePacketChannel::SCRIPT);

public:
    int32_t id = 0;

private:
    template <typename Stream>
    bool Serialize(Stream& stream)
    {
        serialize_bits(stream, id, 32);
        return true;
    }
};
// trains the host's current mission created (create_mission_train), with where they are and how fast they go
class MissionTrains : public Packet
{
    DEFINE_PACKET_TYPE(MissionTrains, ePacketType::MISSION_TRAINS, ePacketChannel::SCRIPT);

public:
    static constexpr int MAX_TRAINS = 4;

    struct Train
    {
        int32_t id = 0;  // the host numbers its mission trains
        uint8_t type = 0;
        bool clockwise = false;
        int32_t node = -1;
        int8_t track = -1;
        CVector spawn{};     // where the mission created it (partners create theirs the same way)
        CVector position{};  // engine now
        float speed = 0;
        float rail = 0;  // engine's distance along its track (what places a train exactly)
        int8_t trackNow = 0;
        int16_t nodeNow = 0;
    };

    uint8_t count = 0;
    Train trains[MAX_TRAINS]{};

private:
    template <typename Stream>
    bool Serialize(Stream& stream)
    {
        serialize_int(stream, count, 0, MAX_TRAINS);
        for (int i = 0; i < count; i++)
        {
            Train& t = trains[i];
            serialize_bits(stream, t.id, 32);
            serialize_bits(stream, t.type, 8);
            serialize_bool(stream, t.clockwise);
            serialize_bits(stream, t.node, 32);
            serialize_bits(stream, t.track, 8);
            serialize_vector(stream, t.spawn);
            serialize_vector(stream, t.position);
            serialize_float(stream, t.speed);
            serialize_float(stream, t.rail);
            serialize_bits(stream, t.trackNow, 8);
            serialize_bits(stream, t.nodeNow, 16);
        }
        return true;
    }
};
}  // namespace Packets::Blips
