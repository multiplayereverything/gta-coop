#pragma once

// "/report <what happened>" in the chat: writes CoopAndreas_reports\report-<time>.txt next to gta_sa.exe with what
// the game knows at that moment (mission, place, players and their connection, network quality, newest crash log),
// for a player to send to whoever fixes the mod. Nothing is sent anywhere by itself.
class CPlaytestReport
{
public:
    // true when the chat line was a report command (it is then not sent as a chat message)
    static bool HandleChatCommand(const std::wstring& line);
};
