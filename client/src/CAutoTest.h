#pragma once

// Automated in-game testing, only active with `--autotest` on the command line.
//   -autoip 127.0.0.1 -autoport 6767 -autoname Tester
// - skips the menu: starts a new game and connects by itself
// - writes CoopAndreas\autotest\status.json twice a second (connection, local player, network players, chat)
// - appends what happens (connect, auth, host, players joining/leaving/spawning, chat, cars, interiors, death)
//   to CoopAndreas\autotest\events.jsonl, so tests can assert on a log instead of screenshots
// - executes lines appended to CoopAndreas\autotest\commands.txt:
//     chat <text> | teleport <x> <y> <z> | vehicle <model> | leavevehicle | heal | kill | skipcutscene
// - mission events: mission_started/ended/passed/failed, cutscene_started/ended, skip_vote_state
// - -autodir <sub> writes to CoopAndreas\autotest\<sub> (several games from one folder)
// testing\ingame-test.ps1 drives this together with headless bots.
class CAutoTest
{
public:
    static inline bool ms_bEnabled = false;
    // passmission: the next 0735 is_keyboard_key_pressed 83 in a mission script returns true, which is Rockstar's
    // debug skip in most mission scripts (goto the mission's own pass routine). Retail always returns false.
    static inline bool ms_bPassRequested = false;

    static void Init();
    static void ProcessMenu(CMenuManager* pMenu);
    static void ProcessGame();
    static void ProcessPad();
    static void OnChatMessage(const char* name, const wchar_t* message);
    // Coop.SetAutotestPassLabel: remembers the pass routine of the running mission script (label as the script encodes it)
    static void SetPassLabel(CRunningScript* script, int label);

    // appends {"t":tick,"ev":type,...fields} to CoopAndreas\autotest\events.jsonl; fields is a JSON fragment or ""
    static void Event(const char* type, const std::string& fields = "");

private:
    static void DetectChanges();
    static void DetectMission();
    static void WriteStatus(bool inGame);
    static void ExecuteCommands();
    static void Execute(const std::string& line);
};
