// UDP network simulator for testing coop over "internet" conditions on one PC.
// Clients connect to --listen; datagrams are relayed to/from the server at --server with added one-way delay,
// jitter and random loss in both directions. One upstream socket per client address (ENet clients keep one port).
//
// usage: CoopAndreasNetSim --listen 16780 --server 127.0.0.1:16770 [--delay 75] [--jitter 15] [--loss 2]
//        (--delay/--jitter in ms one-way, --loss in percent per datagram)

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <queue>
#include <random>
#include <string>
#include <vector>

#pragma comment(lib, "ws2_32.lib")

using Clock = std::chrono::steady_clock;

struct SPending
{
    Clock::time_point due;
    SOCKET from;
    sockaddr_in to;
    std::vector<char> data;
    bool operator>(const SPending& o) const { return due > o.due; }
};

struct SClient
{
    sockaddr_in addr{};
    SOCKET upstream = INVALID_SOCKET;
};

static uint64_t Key(const sockaddr_in& a) { return ((uint64_t)a.sin_addr.s_addr << 16) | a.sin_port; }

int main(int argc, char* argv[])
{
    setvbuf(stdout, nullptr, _IONBF, 0);
    int listenPort = 16780, delay = 75, jitter = 15;
    double loss = 2.0;
    std::string server = "127.0.0.1:16770";
    for (int i = 1; i + 1 < argc; i += 2)
    {
        std::string a = argv[i];
        if (a == "--listen") listenPort = atoi(argv[i + 1]);
        else if (a == "--server") server = argv[i + 1];
        else if (a == "--delay") delay = atoi(argv[i + 1]);
        else if (a == "--jitter") jitter = atoi(argv[i + 1]);
        else if (a == "--loss") loss = atof(argv[i + 1]);
    }

    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);

    sockaddr_in serverAddr{};
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_port = htons((u_short)atoi(server.substr(server.find(':') + 1).c_str()));
    inet_pton(AF_INET, server.substr(0, server.find(':')).c_str(), &serverAddr.sin_addr);

    SOCKET listener = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    sockaddr_in la{};
    la.sin_family = AF_INET;
    la.sin_port = htons((u_short)listenPort);
    la.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(listener, (sockaddr*)&la, sizeof la) != 0)
    {
        printf("bind %d failed\n", listenPort);
        return 1;
    }
    u_long nb = 1;
    ioctlsocket(listener, FIONBIO, &nb);

    std::map<uint64_t, SClient> clients;
    std::map<SOCKET, uint64_t> byUpstream;
    std::priority_queue<SPending, std::vector<SPending>, std::greater<SPending>> pending;
    std::mt19937 rng(1234);
    std::uniform_real_distribution<double> uni(0.0, 100.0);
    std::uniform_int_distribution<int> jit(-jitter, jitter);
    uint64_t relayed = 0, dropped = 0;
    auto lastReport = Clock::now();

    printf("netsim: listen %d -> %s, delay %d ms +-%d, loss %.1f%%\n", listenPort, server.c_str(), delay, jitter, loss);

    auto enqueue = [&](SOCKET from, const sockaddr_in& to, const char* buf, int len) {
        if (uni(rng) < loss)
        {
            dropped++;
            return;
        }
        SPending p{Clock::now() + std::chrono::milliseconds(std::max(0, delay + jit(rng))), from, to,
            std::vector<char>(buf, buf + len)};
        pending.push(std::move(p));
    };

    char buf[65536];
    while (true)
    {
        fd_set rs;
        FD_ZERO(&rs);
        FD_SET(listener, &rs);
        for (auto& [k, c] : clients) FD_SET(c.upstream, &rs);
        timeval tv{0, 1000};
        select(0, &rs, nullptr, nullptr, &tv);

        // client -> server
        sockaddr_in from{};
        int fl = sizeof from;
        int n;
        while ((n = recvfrom(listener, buf, sizeof buf, 0, (sockaddr*)&from, &fl)) > 0)
        {
            uint64_t k = Key(from);
            auto it = clients.find(k);
            if (it == clients.end())
            {
                SClient c;
                c.addr = from;
                c.upstream = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
                ioctlsocket(c.upstream, FIONBIO, &nb);
                it = clients.emplace(k, c).first;
                byUpstream[c.upstream] = k;
                printf("netsim: new client %d\n", ntohs(from.sin_port));
            }
            enqueue(it->second.upstream, serverAddr, buf, n);
            fl = sizeof from;
        }
        // server -> client
        for (auto& [k, c] : clients)
        {
            sockaddr_in sf{};
            int sl = sizeof sf;
            while ((n = recvfrom(c.upstream, buf, sizeof buf, 0, (sockaddr*)&sf, &sl)) > 0)
            {
                enqueue(listener, c.addr, buf, n);
                sl = sizeof sf;
            }
        }
        // deliver due datagrams
        auto now = Clock::now();
        while (!pending.empty() && pending.top().due <= now)
        {
            const SPending& p = pending.top();
            sendto(p.from, p.data.data(), (int)p.data.size(), 0, (const sockaddr*)&p.to, sizeof p.to);
            relayed++;
            pending.pop();
        }
        if (now - lastReport > std::chrono::seconds(10))
        {
            lastReport = now;
            printf("netsim: relayed %llu dropped %llu clients %zu\n", relayed, dropped, clients.size());
        }
    }
}
