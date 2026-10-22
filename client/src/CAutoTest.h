#pragma once

// Automated in-game testing, only active with `--autotest` on the command line.
//   -autoip 127.0.0.1 -autoport 6767 -autoname Tester
// - skips the menu: starts a new game and connects by itself
// - writes CoopAndreas\autotest\status.json twice a second (connection, local player, network players, chat)
// - appends what happens (connect, auth, host, players joining/leaving/spawning, chat, cars, interiors, death)
//   to CoopAndreas\autotest\events.jsonl, so tests can assert on a log instead of screenshots
// - executes lines appended to CoopAndreas\autotest\commands.txt:
//     chat <text> | teleport <x> <y> <z> | vehicle <model> | leavevehicle | heal
// testing\ingame-test.ps1 drives this together with headless bots.
class CAutoTest
{
public:
    static inline bool ms_bEnabled = false;

    static void Init();
    static void ProcessMenu(CMenuManager* pMenu);
    static void ProcessGame();
    static void OnChatMessage(const char* name, const wchar_t* message);

    // appends {"t":tick,"ev":type,...fields} to CoopAndreas\autotest\events.jsonl; fields is a JSON fragment or ""
    static void Event(const char* type, const std::string& fields = "");

private:
    static void DetectChanges();
    static void WriteStatus(bool inGame);
    static void ExecuteCommands();
    static void Execute(const std::string& line);
};
