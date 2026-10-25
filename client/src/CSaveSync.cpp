#include "stdafx.h"
#include "CSaveSync.h"
#include "CAutoTest.h"
#include <CGenericGameStorage.h>
#include <C_PcSave.h>
#include <CStats.h>
#include <CClothes.h>
#include <filesystem>
#include <fstream>

using ChunkPacket = Packets::Blips::SaveFileChunk;

static constexpr uint32_t LOOK_MAGIC = 0x4B4F4F4C;  // "LOOK"

struct SLook
{
    uint32_t magic = LOOK_MAGIC;
    uint32_t version = 1;
    CPedClothesDesc clothes{};
    float fat = 0, muscle = 0;
};

// receiving a save
static uint32_t ms_nTransferId = 0;
static std::vector<uint8_t> ms_transfer;
static uint32_t ms_nReceived = 0;

static std::vector<int> ms_requestedSlots;  // host: partners asked for these slots to be saved and shared
static std::string ms_loadedPath;           // a save was just loaded: put this player's own look back

static uint32_t Crc32(const uint8_t* data, size_t size)
{
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < size; i++)
    {
        crc ^= data[i];
        for (int k = 0; k < 8; k++)
            crc = (crc >> 1) ^ (0xEDB88320 & (0 - (crc & 1)));
    }
    return ~crc;
}

static std::string Escape(const std::string& text)
{
    std::string out;
    for (char c : text)
    {
        if (c == '\\' || c == '"')
            out += '\\';
        out += c;
    }
    return out;
}

static void Say(const char* text, bool toEveryone)
{
    CChat::AddMessage("{c7a6ff}[Coop] {d6dce8}%s", text);
    if (!toEveryone)
        return;
    Packets::System::ChatMessage packet{};
    MultiByteToWideChar(CP_UTF8, 0, text, -1, packet.message, Config::MAX_CHAT_MESSAGE_LENGTH);
    packet.message[Config::MAX_CHAT_MESSAGE_LENGTH] = L'\0';
    GetPacketFactory().Send(packet);
}

std::string CSaveSync::SlotPath(int slot)
{
    CGenericGameStorage::MakeValidSaveName(slot);
    std::string path = CGenericGameStorage::ms_ValidSaveName;
    if (path.size() < 2 || path.compare(path.size() - 2, 2, ".b") != 0)
        path += ".b";
    return path;
}

static void WriteLook(const std::string& savePath)
{
    CPlayerPed* ped = FindPlayerPed(0);
    if (!ped || !ped->m_pPlayerData || !ped->m_pPlayerData->m_pPedClothesDesc)
        return;
    SLook look{};
    look.clothes = *ped->m_pPlayerData->m_pPedClothesDesc;
    look.fat = CStats::GetStatValue(STAT_FAT);
    look.muscle = CStats::GetStatValue(STAT_MUSCLE);
    std::ofstream file(savePath + ".coop", std::ios::binary | std::ios::trunc);
    file.write((const char*)&look, sizeof(look));
}

static bool ApplyLook(const std::string& savePath)
{
    CPlayerPed* ped = FindPlayerPed(0);
    std::ifstream file(savePath + ".coop", std::ios::binary);
    SLook look{};
    if (!ped || !ped->m_pPlayerData || !ped->m_pPlayerData->m_pPedClothesDesc || !file.read((char*)&look, sizeof(look)) ||
        look.magic != LOOK_MAGIC || look.version != 1)
        return false;
    *ped->m_pPlayerData->m_pPedClothesDesc = look.clothes;
    CStats::SetStatValue(STAT_FAT, look.fat);
    CStats::SetStatValue(STAT_MUSCLE, look.muscle);
    CClothes::RebuildPlayer(ped, false);
    return true;
}

// host: send the save file of a slot to everyone
static void ShareSlot(int slot)
{
    std::string path = CSaveSync::SlotPath(slot);
    std::ifstream file(path, std::ios::binary);
    std::vector<uint8_t> data((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (data.empty())
    {
        Say("Could not share the save: the file was not written", true);
        return;
    }

    static ChunkPacket packet{};  // 8 KB of data: not on the stack
    packet.transferId = GetTickCount() | 1;
    packet.slot = (uint8_t)slot;
    packet.totalSize = (uint32_t)data.size();
    packet.crc = Crc32(data.data(), data.size());
    for (uint32_t offset = 0; offset < data.size(); offset += ChunkPacket::MAX_DATA)
    {
        packet.offset = offset;
        packet.length = (uint16_t)(std::min)((size_t)ChunkPacket::MAX_DATA, data.size() - offset);
        memcpy(packet.data, data.data() + offset, packet.length);
        GetPacketFactory().Send(packet);
    }
    CAutoTest::Event("save_shared", "\"slot\":" + std::to_string(slot) + ",\"size\":" + std::to_string(data.size()) +
                                        ",\"crc\":" + std::to_string(packet.crc));
    char text[128];
    snprintf(text, sizeof text, "Game saved for everyone (slot %d). Everyone keeps their own look.", slot + 1);
    Say(text, true);
}

// after this player's game saved a slot (menu or command)
static void OnSaved(int slot)
{
    std::string path = CSaveSync::SlotPath(slot);
    WriteLook(path);
    CAutoTest::Event("game_saved", "\"slot\":" + std::to_string(slot) + ",\"path\":\"" + Escape(path) + "\"");
    if (!CNetwork::m_bAuthenticated || CNetworkPlayerManager::m_pPlayers.empty())
        return;
    if (CLocalPlayer::m_bIsHost)
        ShareSlot(slot);
    else
    {
        Packets::Blips::SaveRequest packet{};
        packet.slot = (uint8_t)slot;
        GetPacketFactory().Send(packet);
    }
}

static char __fastcall SaveSlot_Hook(C_PcSave* This, void*, int slot)
{
    char error = plugin::CallMethodAndReturn<char, 0x619060, C_PcSave*, int>(This, slot);
    if (error == 0)  // 0 = saved
        OnSaved(slot);
    return error;
}

static bool __cdecl GenericLoad_Hook(bool* arg)
{
    bool loaded = CGenericGameStorage::GenericLoad(arg);
    if (loaded)
        ms_loadedPath = CGenericGameStorage::ms_LoadFileNameWithPath;
    return loaded;
}

void CSaveSync::InjectHooks()
{
    patch::RedirectCall(0x578DFA, SaveSlot_Hook);     // save menu -> C_PcSave::SaveSlot
    patch::RedirectCall(0x53C70B, GenericLoad_Hook);  // loading a saved game
}

void CSaveSync::SaveFromCommand(int slot)
{
    if (SaveSlot_Hook(&PcSaveHelper, nullptr, slot) != 0)
        CAutoTest::Event("game_save_failed", "\"slot\":" + std::to_string(slot));
}

void CSaveSync::Process()
{
    // a save was loaded: this player's own look, if one was kept for it
    if (!ms_loadedPath.empty() && FindPlayerPed(0) && FindPlayerPed(0)->m_pPlayerData)
    {
        bool applied = ApplyLook(ms_loadedPath);
        CAutoTest::Event("save_loaded", std::string("\"look\":") + (applied ? "true" : "false") + ",\"path\":\"" + Escape(ms_loadedPath) + "\"");
        ms_loadedPath.clear();
    }

    // host: save the slots partners asked for, when it is safe (never in the middle of a mission or a scene)
    if (!CLocalPlayer::m_bIsHost)
    {
        ms_requestedSlots.clear();
        return;
    }
    if (ms_requestedSlots.empty() || FrontEndMenuManager.m_bMenuActive)
        return;
    CPlayerPed* ped = FindPlayerPed(0);
    bool onMission = CTheScripts::OnAMissionFlag && CTheScripts::ScriptSpace[CTheScripts::OnAMissionFlag];
    if (onMission || CCutsceneMgr::ms_running || !ped || ped->m_fHealth <= 0.0f)
    {
        Say("A player saved, but the host is busy (mission, cutscene or wasted): the save was not shared. Save again later.", true);
        ms_requestedSlots.clear();
        return;
    }
    int slot = ms_requestedSlots.front();
    ms_requestedSlots.erase(ms_requestedSlots.begin());
    SaveFromCommand(slot);
}

void CSaveSync::HandlePacket(const Packets::Blips::SaveRequest& packet)
{
    if (packet.slot < 8 && ms_requestedSlots.size() < 4)
        ms_requestedSlots.push_back(packet.slot);
}

void CSaveSync::HandlePacket(const ChunkPacket& packet)
{
    if (packet.slot >= 8 || packet.totalSize == 0 || packet.totalSize > 4 * 1024 * 1024 ||
        packet.offset + packet.length > packet.totalSize)
        return;
    if (packet.transferId != ms_nTransferId)
    {
        ms_nTransferId = packet.transferId;
        ms_transfer.assign(packet.totalSize, 0);
        ms_nReceived = 0;
    }
    memcpy(ms_transfer.data() + packet.offset, packet.data, packet.length);
    ms_nReceived += packet.length;
    if (ms_nReceived < packet.totalSize)
        return;

    ms_nTransferId = 0;
    if (Crc32(ms_transfer.data(), ms_transfer.size()) != packet.crc)
    {
        Say("A shared save arrived damaged and was not stored.", false);
        CAutoTest::Event("save_received", "\"ok\":false");
        return;
    }

    // keep the previous file of the slot as .bak, then store the host's save and this player's own look for it
    std::string path = SlotPath(packet.slot);
    std::error_code ec;
    if (std::filesystem::exists(path, ec))
        std::filesystem::copy_file(path, path + ".bak", std::filesystem::copy_options::overwrite_existing, ec);
    {
        std::ofstream file(path, std::ios::binary | std::ios::trunc);
        file.write((const char*)ms_transfer.data(), ms_transfer.size());
    }
    WriteLook(path);
    ms_transfer.clear();
    ms_transfer.shrink_to_fit();

    CAutoTest::Event("save_received", "\"ok\":true,\"slot\":" + std::to_string(packet.slot) + ",\"crc\":" + std::to_string(packet.crc) +
                                          ",\"path\":\"" + Escape(path) + "\"");
    char text[128];
    snprintf(text, sizeof text, "The host's save was stored in slot %d (your look is kept for it).", packet.slot + 1);
    Say(text, false);
}

bool CSaveSync::ApplyLookForSlot(int slot)
{
    return ApplyLook(SlotPath(slot));
}
