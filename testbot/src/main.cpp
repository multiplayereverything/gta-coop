// CoopAndreas headless test bot.
// Joins a server like a real player, walks in a circle, sends one chat message,
// and checks that it receives the other players' sync. Prints one RESULT line
// (JSON) and exits 0 on pass, 1 on fail, 2 when it cannot connect.
//
// usage: CoopAndreasBot [--host 127.0.0.1] [--port 6767] [--name Bot1] [--index 0]
//                       [--duration 15] [--expect-peers N] [--expect-refused] [--no-chat]

#include "stdafx.h"
#include "network/packets/system.h"
#include "network/packets/players.h"

#include <chrono>
#include <set>
#include <thread>

void CPacketFactory::RegisterPacket(Packet* pPacket)
{
    m_map[static_cast<uint16_t>(pPacket->GetType())] = pPacket;
}

Packet* CPacketFactory::Find(ePacketType type)
{
    auto it = m_map.find(static_cast<uint16_t>(type));
    return it == m_map.end() ? nullptr : it->second;
}

struct SArgs
{
    std::string host = "127.0.0.1";
    uint16_t port = Config::DEFAULT_PORT;
    std::string name = "Bot1";
    int index = 0;
    int duration = 15;
    int expectPeers = -1;
    bool expectRefused = false;
    bool chat = true;
};

struct SPeer
{
    std::string name;
    int onFootUpdates = 0;
    int chatMessages = 0;
    bool left = false;
    CVector lastPos{};
};

static ENetHost* g_pHost = nullptr;
static ENetPeer* g_pPeer = nullptr;
static server_time_t g_serverTime = 0;
static uint8_t g_buffer[10 * 1024];

static void SendPacket(Packet& packet)
{
    serialize::WriteStream stream(g_buffer, sizeof(g_buffer));

    uint16_t packetType = static_cast<uint16_t>(packet.GetType());
    stream.SerializeBits(packetType, 16);
    if (packet.GetChannel() != ePacketChannel::SYSTEM)
    {
        packet.serverTime = g_serverTime;
        stream.SerializeBits(packet.serverTime, 32);
    }
    if (!packet.SerializeWrite(stream))
    {
        logger::warn("SerializeWrite failed for packet #%d", packetType);
        return;
    }
    stream.Flush();

    uint32_t flags = GetChannelReliability(packet.GetChannel()) == ePacketReliability::RELIABLE
                         ? ENET_PACKET_FLAG_RELIABLE
                         : 0;
    ENetPacket* pENetPacket = enet_packet_create(stream.GetData(), stream.GetBytesProcessed(), flags);
    enet_peer_send(g_pPeer, static_cast<uint8_t>(packet.GetChannel()), pENetPacket);
}

static Packet* ReadPacket(const uint8_t* data, size_t size)
{
    serialize::ReadStream stream(data, (int)size);

    uint32_t packetType = 0;
    if (!stream.SerializeBits(packetType, 16))
        return nullptr;

    Packet* pPacket = GetPacketFactory().Find(static_cast<ePacketType>(packetType));
    if (pPacket == nullptr)
        return nullptr;  // a packet type this bot does not care about

    if (pPacket->GetChannel() != ePacketChannel::SYSTEM)
    {
        if (!stream.SerializeBits(pPacket->serverTime, 32))
            return nullptr;
        g_serverTime = std::max(g_serverTime, pPacket->serverTime);
    }

    if (!pPacket->SerializeRead(stream))
    {
        logger::warn("SerializeRead failed for packet #%u", packetType);
        return nullptr;
    }
    return pPacket;
}

static SArgs ParseArgs(int argc, char* argv[])
{
    SArgs args;
    for (int i = 1; i < argc; i++)
    {
        std::string a = argv[i];
        auto next = [&]() -> const char* { return (i + 1 < argc) ? argv[++i] : ""; };

        if (a == "--host") args.host = next();
        else if (a == "--port") args.port = (uint16_t)atoi(next());
        else if (a == "--name") args.name = next();
        else if (a == "--index") args.index = atoi(next());
        else if (a == "--duration") args.duration = atoi(next());
        else if (a == "--expect-peers") args.expectPeers = atoi(next());
        else if (a == "--expect-refused") args.expectRefused = true;
        else if (a == "--no-chat") args.chat = false;
    }
    return args;
}

static void PrintResult(const SArgs& args, bool pass, const char* status, playerid_t myId,
    const std::map<uint32_t, SPeer>& peers)
{
    printf("RESULT {\"name\":\"%s\",\"pass\":%s,\"status\":\"%s\",\"id\":%u,\"peers\":[", args.name.c_str(),
        pass ? "true" : "false", status, myId.value());
    bool first = true;
    for (const auto& [id, peer] : peers)
    {
        printf("%s{\"id\":%u,\"name\":\"%s\",\"onfoot\":%d,\"chat\":%d,\"left\":%s}", first ? "" : ",", id,
            peer.name.c_str(), peer.onFootUpdates, peer.chatMessages, peer.left ? "true" : "false");
        first = false;
    }
    printf("]}\n");
    fflush(stdout);
}

int main(int argc, char* argv[])
{
    SArgs args = ParseArgs(argc, argv);
    std::map<uint32_t, SPeer> peers;
    playerid_t myId{};

    if (enet_initialize() != 0)
    {
        PrintResult(args, false, "enet_init_failed", myId, peers);
        return 2;
    }

    g_pHost = enet_host_create(nullptr, 1, (int)ePacketChannel::COUNT, 0, 0);

    ENetAddress address{};
    enet_address_set_host(&address, args.host.c_str());
    address.port = args.port;

    uint32_t packedVersion = semver_parse(COOPANDREAS_VERSION, nullptr);
    g_pPeer = enet_host_connect(g_pHost, &address, (int)ePacketChannel::COUNT, packedVersion);

    ENetEvent event{};
    bool connected = enet_host_service(g_pHost, &event, 5000) > 0 && event.type == ENET_EVENT_TYPE_CONNECT;
    if (!connected)
    {
        enet_peer_reset(g_pPeer);
        enet_host_destroy(g_pHost);
        enet_deinitialize();
        // a full server rejects the ENet connection itself (no free peer slot)
        PrintResult(args, args.expectRefused, "refused", myId, peers);
        return args.expectRefused ? 0 : 2;
    }

    Packets::System::PlayerConnected connectedPacket{};
    connectedPacket.payload.playerid = -1;
    connectedPacket.payload.isAlreadyConnected = false;
    connectedPacket.payload.version = packedVersion;
    strncpy_s(connectedPacket.payload.name, args.name.c_str(), Config::MAX_NICKNAME_LENGTH);
    SendPacket(connectedPacket);

    // spread bots around Grove Street so they are easy to spot in game
    const CVector center(2495.0f + 4.0f * args.index, -1670.0f, 13.34f);
    const float radius = 3.0f;
    const float angularSpeed = 0.8f;  // rad/s, roughly walking pace

    auto start = std::chrono::steady_clock::now();
    auto lastSync = start;
    bool chatSent = !args.chat;
    const char* status = "ok";

    while (true)
    {
        auto now = std::chrono::steady_clock::now();
        float t = std::chrono::duration<float>(now - start).count();
        if (t >= args.duration)
            break;

        while (enet_host_service(g_pHost, &event, 5) > 0)
        {
            if (event.type == ENET_EVENT_TYPE_DISCONNECT)
            {
                status = myId.valid() ? "disconnected" : "refused";
                goto done;
            }
            if (event.type != ENET_EVENT_TYPE_RECEIVE)
                continue;

            Packet* pPacket = ReadPacket(event.packet->data, event.packet->dataLength);
            enet_packet_destroy(event.packet);
            if (pPacket == nullptr)
                continue;

            switch (pPacket->GetType())
            {
                case ePacketType::PLAYER_HANDSHAKE:
                {
                    myId = static_cast<Packets::System::PlayerHandshake*>(pPacket)->yourid;
                    logger::info("%s: joined as %s", args.name.c_str(), to_string(myId).c_str());
                    break;
                }
                case ePacketType::PLAYER_CONNECTED:
                {
                    auto* p = static_cast<Packets::System::PlayerConnected*>(pPacket);
                    peers[p->payload.GetPlayerId().value()].name = p->payload.name;
                    break;
                }
                case ePacketType::PLAYER_DISCONNECTED:
                {
                    auto* p = static_cast<Packets::System::PlayerDisconnected*>(pPacket);
                    if (p->payload.playerid == -1)
                    {
                        status = p->payload.reason == Packets::System::PlayerDisconnected::DISCONNECTION_REASON_NAME_TAKEN
                                     ? "name_taken"
                                     : "version_mismatch";
                        goto done;
                    }
                    // keep the record: bots finish at different times, the result is about who we saw
                    peers[p->payload.GetPlayerId().value()].left = true;
                    break;
                }
                case ePacketType::PLAYER_ONFOOT_UPDATE:
                {
                    auto* p = static_cast<Packets::Players::OnFootUpdate*>(pPacket);
                    SPeer& peer = peers[p->senderPlayerid.value.value()];
                    peer.onFootUpdates++;
                    peer.lastPos = p->vecPos;
                    break;
                }
                case ePacketType::PLAYER_CHAT_MESSAGE:
                {
                    auto* p = static_cast<Packets::System::ChatMessage*>(pPacket);
                    peers[p->senderPlayerid.value.value()].chatMessages++;
                    break;
                }
                default:
                    break;
            }
        }

        if (!myId.valid())
            continue;

        // 20 Hz on-foot sync, like the game client
        if (now - lastSync >= std::chrono::milliseconds(50))
        {
            lastSync = now;
            float a = t * angularSpeed;

            Packets::Players::OnFootUpdate update{};
            update.vecPos = CVector(center.x + radius * cosf(a), center.y + radius * sinf(a), center.z);
            update.vecMoveSpeed = CVector(-radius * angularSpeed * sinf(a) / 50.0f,
                radius * angularSpeed * cosf(a) / 50.0f, 0.0f);
            update.currentRotation = NormalizeRadianAngle(a + PI);
            update.aimingRotation = update.currentRotation;
            SendPacket(update);
        }

        // say hello once everyone had time to join
        if (!chatSent && t >= 4.0f)
        {
            chatSent = true;
            Packets::System::ChatMessage chat{};
            wchar_t text[Config::MAX_CHAT_MESSAGE_LENGTH + 1];
            swprintf(text, ARRAY_SIZE(text), L"hello from %hs", args.name.c_str());
            wcsncpy_s(chat.message, text, Config::MAX_CHAT_MESSAGE_LENGTH);
            SendPacket(chat);
        }
    }

done:
    bool pass = myId.valid() && strcmp(status, "ok") == 0;
    if (pass && args.expectPeers >= 0)
    {
        pass = (int)peers.size() == args.expectPeers;
        for (const auto& [id, peer] : peers)
        {
            // at 20 Hz over several seconds anything under 20 means sync is broken
            if (peer.onFootUpdates < 20 || (args.chat && peer.chatMessages < 1))
                pass = false;
        }
    }
    if (args.expectRefused)
        pass = strcmp(status, "refused") == 0;

    PrintResult(args, pass, status, myId, peers);

    if (g_pPeer != nullptr && strcmp(status, "ok") == 0)
    {
        enet_peer_disconnect(g_pPeer, 0);
        while (enet_host_service(g_pHost, &event, 500) > 0)
        {
            if (event.type == ENET_EVENT_TYPE_RECEIVE)
                enet_packet_destroy(event.packet);
            else if (event.type == ENET_EVENT_TYPE_DISCONNECT)
                break;
        }
    }
    enet_host_destroy(g_pHost);
    enet_deinitialize();
    return pass ? 0 : 1;
}
