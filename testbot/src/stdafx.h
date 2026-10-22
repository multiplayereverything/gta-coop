#pragma once

// Headless test client. Compiled as a client (COOP_CLIENT) so the shared packet
// headers serialize exactly like the real game does, but without the game.

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <map>
#include <string>
#include <unordered_map>

#define ARRAY_SIZE(a) (sizeof(a) / sizeof(a[0]))

#include "enet/enet.h"

#include "config.h"
#include "semver.h"
#include "logger.h"

class CEntity;
class Packet;
enum class ePacketType : uint16_t;

class CPacketFactory
{
public:
    void RegisterPacket(Packet* pPacket);
    Packet* Find(ePacketType type);

    std::unordered_map<uint16_t, Packet*> m_map;
};

extern inline CPacketFactory& GetPacketFactory()
{
    static CPacketFactory factory;
    return factory;
}

#include "network/packet.h"
#include "network/packet_types.h"
