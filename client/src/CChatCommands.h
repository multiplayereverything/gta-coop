#pragma once

#include "network/packets/blips.h"

// Chat commands (F6, then "/help"): teleports between players, starting story missions, and a few debug helpers.
// The line is taken from the chat right away and run on the next game frame.
class CChatCommands
{
public:
    // true when the line is a command (it is then not sent as a chat message)
    static bool Handle(const std::wstring& line);
    static void Process();
    static void HandleTeleportRequest(const Packets::Blips::TeleportPlayerRequest& packet);
};
