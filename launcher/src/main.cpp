#include <windows.h>
#include "launcher.h"

#pragma comment(linker, \
    "\"/manifestdependency:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int)
{
    wchar_t path[MAX_PATH];
    GetModuleFileNameW(NULL, path, MAX_PATH);
    wcscat_s(path, MAX_PATH, L".manifest");

    if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES)
    {
        wchar_t buffer[128 + MAX_PATH];
        wsprintfW(buffer,
            L"Could not find %s.\n\nCoopAndreas Launcher won't run.\n\nReinstall the mod to play CoopAndreas.", path);
        MessageBoxW(NULL, buffer, L"CoopAndreas Launcher Error", MB_ICONERROR | MB_OK);
        return 1;
    }

    // this fork needs no beta serial key: start the game in coop mode right away
    Launcher::LaunchProcess("\"gta_sa.exe\" --coop");
    return 0;
}
