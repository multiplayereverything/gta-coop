#include "stdafx.h"
#include "CUserTrackSync.h"
#include "CAutoTest.h"
#include <filesystem>
#include <fstream>
#include <deque>
#include <unordered_set>

namespace fs = std::filesystem;
using ListPacket = Packets::Blips::UserTrackList;
using ChunkPacket = Packets::Blips::UserTrackChunk;

static constexpr uint32_t MAX_SONG_SIZE = 40 * 1024 * 1024;
static constexpr int CHUNKS_PER_FRAME = 4;  // ~28 KB per frame

struct SWanted
{
    playerid_t owner;
    std::string name;
    uint32_t size;
};

struct SUpload
{
    playerid_t to;
    std::string name;
    std::ifstream file;
    uint32_t size, offset;
};

static std::deque<SWanted> ms_wanted;          // songs other players have and this one does not
static std::unordered_set<std::string> ms_known;  // asked for already (or failed) this session
static std::string ms_downloading;             // the song coming in now
static playerid_t ms_downloadOwner{};
static uint32_t ms_downloadSize = 0, ms_downloadReceived = 0, ms_lastChunkAt = 0;
static int ms_nRequestTries = 0;          // a request can get lost (e.g. sent the moment a player joins): asked again
static uint32_t ms_nAuthenticatedAt = 0;
static std::ofstream ms_downloadFile;
static std::deque<SUpload*> ms_uploads;
static uint32_t ms_nLastListAt = 0;
static int ms_nReceived = 0;

std::string CUserTrackSync::Folder()
{
    return (fs::path((const char*)0xC92368) / "User Tracks").string();  // the game's user files folder
}

int CUserTrackSync::GetReceivedCount()
{
    return ms_nReceived;
}

// plain file names of songs the game plays; nothing that could point outside the folder
static bool IsSongName(const std::string& name)
{
    if (name.empty() || name.size() >= ListPacket::MAX_NAME || name.find_first_of("\\/:*?\"<>|") != std::string::npos ||
        name.find("..") != std::string::npos)
        return false;
    std::string ext = fs::u8path(name).extension().string();
    for (char& c : ext)
        c = (char)tolower((unsigned char)c);
    return ext == ".mp3" || ext == ".ogg" || ext == ".wav" || ext == ".wma";
}

// the file really is that kind of audio: a renamed or broken file made the user-track radio freeze the game for
// seconds when it stopped or retuned (testing/usertrack-hang.ps1), and sharing would put it on every player's PC
static bool LooksLikeAudio(const fs::path& file, const std::string& name)
{
    std::string ext = fs::u8path(name).extension().string();
    for (char& c : ext)
        c = (char)tolower((unsigned char)c);
    uint8_t h[12] = {};
    std::ifstream f(file, std::ios::binary);
    if (!f.read((char*)h, sizeof(h)))
        return false;
    if (ext == ".mp3")
        return memcmp(h, "ID3", 3) == 0 || (h[0] == 0xFF && (h[1] & 0xE0) == 0xE0);
    if (ext == ".ogg")
        return memcmp(h, "OggS", 4) == 0;
    if (ext == ".wav")
        return memcmp(h, "RIFF", 4) == 0 && memcmp(h + 8, "WAVE", 4) == 0;
    if (ext == ".wma")
        return memcmp(h, "\x30\x26\xB2\x75\x8E\x66\xCF\x11", 8) == 0;  // ASF header
    return false;
}

static void SendList()
{
    std::error_code ec;
    ListPacket packet{};
    for (const auto& entry : fs::directory_iterator(CUserTrackSync::Folder(), ec))
    {
        if (packet.count >= ListPacket::MAX_ENTRIES)
        {
            GetPacketFactory().Send(packet);
            packet.count = 0;
        }
        std::string name = entry.path().filename().u8string();
        uint64_t size = entry.is_regular_file(ec) ? entry.file_size(ec) : 0;
        if (!IsSongName(name) || size == 0 || size > MAX_SONG_SIZE || !LooksLikeAudio(entry.path(), name))
            continue;
        strcpy_s(packet.names[packet.count], name.c_str());
        packet.sizes[packet.count] = (uint32_t)size;
        packet.count++;
    }
    if (packet.count > 0)
        GetPacketFactory().Send(packet);
}

static void Say(const std::string& text)
{
    CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}%s", text.c_str());
}

static void FinishDownload(bool ok)
{
    ms_downloadFile.close();
    fs::path part = fs::u8path(CUserTrackSync::Folder()) / fs::u8path(ms_downloading + ".coopdl");
    std::error_code ec;
    if (ok && !LooksLikeAudio(part, ms_downloading))
    {
        CAutoTest::Event("user_track_rejected", "\"size\":" + std::to_string(ms_downloadSize));
        ok = false;
    }
    if (ok)
    {
        fs::rename(part, fs::u8path(CUserTrackSync::Folder()) / fs::u8path(ms_downloading), ec);
        ms_nReceived++;
        CAutoTest::Event("user_track_received", "\"size\":" + std::to_string(ms_downloadSize));
        if (ms_wanted.empty())
            Say("New user tracks from your friends are in your User Tracks folder. To hear them: Options > Audio Setup > "
                "User Track Options > Scan User Tracks (or restart the game).");
    }
    else
        fs::remove(part, ec);
    ms_downloading.clear();
}

static void SendRequest()
{
    Packets::Blips::UserTrackRequest request{};
    request.owner = ms_downloadOwner;
    strcpy_s(request.name, ms_downloading.c_str());
    GetPacketFactory().Send(request);
    ms_nRequestTries++;
    ms_lastChunkAt = GetTickCount();
}

static void StartNextDownload()
{
    std::error_code ec;
    while (ms_downloading.empty() && !ms_wanted.empty())
    {
        SWanted next = ms_wanted.front();
        ms_wanted.pop_front();
        fs::path target = fs::u8path(CUserTrackSync::Folder()) / fs::u8path(next.name);
        if (fs::exists(target, ec) || !CNetworkPlayerManager::GetPlayer(next.owner))
            continue;
        fs::create_directories(target.parent_path(), ec);
        ms_downloadFile.open(fs::path(target.wstring() + L".coopdl"), std::ios::binary | std::ios::trunc);
        if (!ms_downloadFile)
            continue;
        ms_downloading = next.name;
        ms_downloadOwner = next.owner;
        ms_downloadSize = next.size;
        ms_downloadReceived = 0;
        ms_lastChunkAt = GetTickCount();

        ms_nRequestTries = 0;
        SendRequest();
        CAutoTest::Event("user_track_requested", "\"size\":" + std::to_string(next.size));
    }
}

void CUserTrackSync::Process()
{
    if (!CNetwork::m_bAuthenticated || CNetworkPlayerManager::m_pPlayers.empty())
    {
        ms_nAuthenticatedAt = 0;
        return;
    }
    if (ms_nAuthenticatedAt == 0)
        ms_nAuthenticatedAt = GetTickCount();
    if (GetTickCount() - ms_nAuthenticatedAt < 5000)  // just joined: the server may not route our packets yet
        return;

    // tell the others what this game has (also reaches players who joined later)
    if (GetTickCount() - ms_nLastListAt > 20000)
    {
        ms_nLastListAt = GetTickCount();
        SendList();
    }

    // nothing came for a request: ask again (3 times), then a download that stopped (owner left) is dropped
    if (!ms_downloading.empty() && ms_downloadReceived == 0 && GetTickCount() - ms_lastChunkAt > 5000 && ms_nRequestTries < 3)
        SendRequest();
    if (!ms_downloading.empty() && GetTickCount() - ms_lastChunkAt > 30000)
    {
        CAutoTest::Event("user_track_timeout", "\"got\":" + std::to_string(ms_downloadReceived) + ",\"size\":" + std::to_string(ms_downloadSize));
        FinishDownload(false);
    }
    StartNextDownload();

    // uploads: a few pieces per frame, oldest request first
    static ChunkPacket chunk{};  // 7 KB of data: not on the stack
    for (int sent = 0; sent < CHUNKS_PER_FRAME && !ms_uploads.empty();)
    {
        SUpload* upload = ms_uploads.front();
        if (!CNetworkPlayerManager::GetPlayer(upload->to) || !upload->file || upload->offset >= upload->size)
        {
            delete upload;
            ms_uploads.pop_front();
            continue;
        }
        chunk.to = upload->to;
        strcpy_s(chunk.name, upload->name.c_str());
        chunk.size = upload->size;
        chunk.offset = upload->offset;
        chunk.length = (uint16_t)(std::min)((uint32_t)ChunkPacket::MAX_DATA, upload->size - upload->offset);
        upload->file.read((char*)chunk.data, chunk.length);
        if (upload->file.gcount() != chunk.length)
        {
            upload->size = 0;  // file changed while sending: stop, the receiver times out
            continue;
        }
        GetPacketFactory().Send(chunk);
        upload->offset += chunk.length;
        sent++;
    }
}

void CUserTrackSync::HandlePacket(const ListPacket& packet)
{
    std::error_code ec;
    for (int i = 0; i < packet.count; i++)
    {
        std::string name(packet.names[i], strnlen(packet.names[i], ListPacket::MAX_NAME));
        if (!IsSongName(name) || packet.sizes[i] == 0 || packet.sizes[i] > MAX_SONG_SIZE || ms_known.count(name))
            continue;
        ms_known.insert(name);
        if (fs::exists(fs::u8path(Folder()) / fs::u8path(name), ec))
            continue;  // already have a song by that name (never overwritten)
        ms_wanted.push_back({packet.senderPlayerid.value, name, packet.sizes[i]});
    }
}

void CUserTrackSync::HandlePacket(const Packets::Blips::UserTrackRequest& packet)
{
    std::string name(packet.name, strnlen(packet.name, ListPacket::MAX_NAME));
    std::error_code ec;
    fs::path path = fs::u8path(Folder()) / fs::u8path(name);
    if (!IsSongName(name) || !fs::is_regular_file(path, ec) || ms_uploads.size() >= 8)
        return;
    for (SUpload* upload : ms_uploads)
    {
        if (upload->to == packet.senderPlayerid.value && upload->name == name)
            return;  // asked again while it is already on its way
    }
    uint64_t size = fs::file_size(path, ec);
    if (ec || size == 0 || size > MAX_SONG_SIZE)
        return;
    CAutoTest::Event("user_track_upload", "\"size\":" + std::to_string(size));
    SUpload* upload = new SUpload{packet.senderPlayerid.value, name, std::ifstream(path, std::ios::binary), (uint32_t)size, 0};
    ms_uploads.push_back(upload);
}

void CUserTrackSync::HandlePacket(const ChunkPacket& packet)
{
    std::string name(packet.name, strnlen(packet.name, ListPacket::MAX_NAME));
    if (ms_downloading.empty() || name != ms_downloading || !(packet.senderPlayerid.value == ms_downloadOwner) ||
        packet.size != ms_downloadSize || packet.offset != ms_downloadReceived || packet.length > ChunkPacket::MAX_DATA)
    {
        static int logged = 0;
        if (logged++ < 5)
            CAutoTest::Event("user_track_chunk_ignored", "\"offset\":" + std::to_string(packet.offset) + ",\"expected\":" + std::to_string(ms_downloadReceived) + ",\"downloading\":" + std::to_string(!ms_downloading.empty()));
        return;
    }
    ms_downloadFile.write((const char*)packet.data, packet.length);
    ms_downloadReceived += packet.length;
    ms_lastChunkAt = GetTickCount();
    if (ms_downloadReceived >= ms_downloadSize)
        FinishDownload((bool)ms_downloadFile);
}
