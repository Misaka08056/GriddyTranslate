#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <wchar.h>

/* Standalone Windows launcher: no installation, .NET, Python or Codex required.
 * Only this process and its child receive the RTSS workaround. No mutex is used.
 */
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, LPWSTR arguments, int show) {
    (void)instance; (void)previous; (void)show;
    wchar_t folder[32768];
    if (!GetModuleFileNameW(NULL, folder, 32768)) return 1;
    wchar_t *slash = wcsrchr(folder, L'\\');
    if (!slash) return 1;
    *slash = 0;
    size_t capacity = wcslen(folder) + wcslen(arguments) + 256;
    wchar_t *command = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, capacity * sizeof(wchar_t));
    if (!command) return 1;
    wcscpy(command, L"\"");
    wcscat(command, folder);
    wcscat(command, L"\\GriddyTranslate.runtime.exe\" ");
    wcscat(command, arguments);
    SetEnvironmentVariableW(L"DISABLE_RTSS_LAYER", L"1");
    SetEnvironmentVariableW(L"VK_LOADER_LAYERS_DISABLE", L"VK_LAYER_RTSS");
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_SHOWNORMAL;
    BOOL started = CreateProcessW(NULL, command, NULL, NULL, FALSE, 0, NULL, folder, &startup, &process);
    HeapFree(GetProcessHeap(), 0, command);
    if (!started) {
        MessageBoxW(NULL, L"无法启动翻译器。请先解压整个 ZIP，并让 exe、runtime.exe、runtime.pck 和 DLL 保持在同一个文件夹。", L"GriddyTranslate", MB_OK | MB_ICONERROR);
        return 1;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return 0;
}
