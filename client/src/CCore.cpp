#include "stdafx.h"
#include "CCrashLog.h"
#include "Commands/CCustomCommandRegistrar.h"
#include "CDiscordRPC.h"
#include <COpCodeSync.h>
#include <CCustomMenuManager.h>
#include <winuser.h>
#include <Debug/CImGui.h>
#include "CAutoTest.h"

semver_t CCore::Version;

WNDPROC prevWndProc;

LRESULT CALLBACK WindowProc(HWND hWnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    // the game keeps running unfocused (ForegroundApp forced, see CPatch), so it no longer pauses and resets the
    // keyboard on alt-tab: keys held at that moment (Alt = walk, movement keys) never got their key-up and stayed
    // "pressed" - after alt-tabbing during a cutscene the player could not move. Release everything on focus changes.
    if (message == WM_ACTIVATEAPP || message == WM_KILLFOCUS || message == WM_SETFOCUS)
    {
        memset((void*)0xB72CB0, 0, 0x270 * 3);  // CPad::TempKeyState, OldKeyState, NewKeyState (CKeyboardState each)
        CPad::GetPad(0)->PCTempKeyState = CControllerState();
    }
    CChat::WndProc(hWnd, message, wParam, lParam);
    CCustomMenuManager::WndProc(hWnd, message, wParam, lParam);
    if (CImGui::WndProc(hWnd, message, wParam, lParam))
    {
        return TRUE;
    }
    return CallWindowProcW(prevWndProc, hWnd, message, wParam, lParam);
}

void InitWndProc()
{
    HWND hWnd = *(HWND*)0xC97C1C;

    SetWindowTextW(hWnd, L"CoopAndreas");
    RsGlobal.appName = "CoopAndreas";

    if (hWnd)
    {
        prevWndProc = (WNDPROC)GetWindowLongW(hWnd, GWL_WNDPROC);
        SetWindowLongW(hWnd, GWL_WNDPROC, (LONG)WindowProc);
        return;
    }
}

uintptr_t WinMain_AfterWindowInit_ptr = 0x0;
void WinMain_AfterWindowInit()
{
    CPatch::ReclaimGameProcessHook();  // every ASI is loaded by now
    InitWndProc();
    plugin::CallDyn(WinMain_AfterWindowInit_ptr);
}

void CCore::Init()
{
    CCrashLog::ms_lpPreviousFilter = SetUnhandledExceptionFilter(CCrashLog::ExceptionHandler);

    LPTSTR cmd = GetCommandLine();
    // --coopd0 .. --coopd3: local multi-instance debug run, the digit picks the window slot
    if (const char* debugArg = strstr(cmd, "--coopd"))
    {
        char slot = debugArg[7];
        if (slot >= '0' && slot <= '3')
        {
            ms_bDebug = true;
            ms_nRunIndex = slot - '0';
        }
    }

    CAutoTest::Init();

    gvm.Detect();
#ifdef _DEV
    // a hidden test game (-autohide) gets no console: showing it takes keyboard focus from the user
    if (!CAutoTest::ms_bEnabled || !strstr(GetCommandLineA(), "-autohide"))
        CCore::AllocateConsole();
#endif
    CImGui::Init();
    WinMain_AfterWindowInit_ptr = injector::GetBranchDestination(0x748995).as_int();
    patch::RedirectCall(0x748995, WinMain_AfterWindowInit);
    CCustomMenuManager::Init();
    CPatch::ApplyPatches();
    CHook::Init();
    CCustomCommandRegistrar::Register();
    CDXFont::Init();
    CDiscordRPC::Init();
    COpCodeSync::Init();
    // Main.cpp registered the gameProcessEvent handlers before calling us, so the hook is installed now
    CPatch::RememberGameProcessHook();
    Events::initGameEvent.after += []
    {
        CPatch::ReclaimGameProcessHook();
        CPatch::TemporaryPatches();
        // init CNetworking async
        CNetwork::Start();
    };
    Events::initRwEvent += [] { CPatch::PatchFramerate(); };

    /*Events::initScriptsEvent.after += []
    {
        CPatch::TemporaryPatches();
    };*/
    gameShutdownEvent.before += []
    {
        // disconnect from server
        CDiscordRPC::Destroy();
        CNetwork::Disconnect();
    };
    semver_parse(COOPANDREAS_VERSION, &CCore::Version);
}

void CCore::AllocateConsole()
{
    AllocConsole();
    freopen("CONOUT$", "w", stdout);
    freopen("CONIN$", "r", stdin);

    DWORD dwMode = 0;
    HANDLE hOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    GetConsoleMode(hOutput, &dwMode);
    dwMode |= ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
    SetConsoleMode(hOutput, dwMode);

    HWND hWnd = GetConsoleWindow();
    ShowWindow(hWnd, SW_SHOWMINIMIZED);
}
