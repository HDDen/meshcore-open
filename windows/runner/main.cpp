#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <string>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#ifndef FLUTTER_VERSION
#define FLUTTER_VERSION "1.0.0"
#endif

namespace {
constexpr wchar_t kWindowStateRegKey[] =
    L"Software\\com.meshcore\\meshcore_open\\WindowState";
constexpr wchar_t kWindowWidthRegValue[] = L"LogicalWidth";
constexpr wchar_t kWindowHeightRegValue[] = L"LogicalHeight";
constexpr unsigned int kDefaultWindowWidth = 1280;
constexpr unsigned int kDefaultWindowHeight = 720;
constexpr unsigned int kMinSavedWindowWidth = 320;
constexpr unsigned int kMinSavedWindowHeight = 240;
WNDPROC g_original_window_proc = nullptr;

std::wstring GetWindowTitle() {
  std::wstring title = L"meshcore_open (Advanced mod) ";
  constexpr char version[] = FLUTTER_VERSION;
  for (char character : version) {
    if (character == '\0' || character == '+') {
      break;
    }
    title.push_back(static_cast<wchar_t>(character));
  }
  return title;
}

DWORD ReadWindowSizeValue(const wchar_t* name, DWORD fallback) {
  DWORD value = fallback;
  DWORD value_size = sizeof(value);
  RegGetValue(HKEY_CURRENT_USER, kWindowStateRegKey, name, RRF_RT_REG_DWORD,
              nullptr, &value, &value_size);
  return value;
}

Win32Window::Size LoadWindowSize() {
  const DWORD width =
      ReadWindowSizeValue(kWindowWidthRegValue, kDefaultWindowWidth);
  const DWORD height =
      ReadWindowSizeValue(kWindowHeightRegValue, kDefaultWindowHeight);
  return Win32Window::Size(
      width >= kMinSavedWindowWidth ? width : kDefaultWindowWidth,
      height >= kMinSavedWindowHeight ? height : kDefaultWindowHeight);
}

void SaveWindowSize(HWND window) {
  if (::IsIconic(window)) {
    return;
  }

  RECT rect;
  if (!::GetWindowRect(window, &rect)) {
    return;
  }

  const UINT dpi = FlutterDesktopGetDpiForHWND(window);
  const UINT safe_dpi = dpi == 0 ? 96 : dpi;
  const DWORD width = ::MulDiv(rect.right - rect.left, 96, safe_dpi);
  const DWORD height = ::MulDiv(rect.bottom - rect.top, 96, safe_dpi);
  if (width < kMinSavedWindowWidth || height < kMinSavedWindowHeight) {
    return;
  }

  HKEY key;
  if (::RegCreateKeyEx(HKEY_CURRENT_USER, kWindowStateRegKey, 0, nullptr, 0,
                       KEY_SET_VALUE, nullptr, &key, nullptr) !=
      ERROR_SUCCESS) {
    return;
  }

  ::RegSetValueEx(key, kWindowWidthRegValue, 0, REG_DWORD,
                  reinterpret_cast<const BYTE*>(&width), sizeof(width));
  ::RegSetValueEx(key, kWindowHeightRegValue, 0, REG_DWORD,
                  reinterpret_cast<const BYTE*>(&height), sizeof(height));
  ::RegCloseKey(key);
}

LRESULT CALLBACK WindowStateProc(HWND window,
                                 UINT message,
                                 WPARAM wparam,
                                 LPARAM lparam) {
  if (message == WM_EXITSIZEMOVE || message == WM_CLOSE) {
    SaveWindowSize(window);
  }
  if (g_original_window_proc == nullptr) {
    return ::DefWindowProc(window, message, wparam, lparam);
  }
  return ::CallWindowProc(g_original_window_proc, window, message, wparam,
                          lparam);
}

void TrackWindowSize(HWND window) {
  if (window == nullptr) {
    return;
  }
  g_original_window_proc = reinterpret_cast<WNDPROC>(
      ::SetWindowLongPtr(window, GWLP_WNDPROC,
                         reinterpret_cast<LONG_PTR>(WindowStateProc)));
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size = LoadWindowSize();
  const std::wstring window_title = GetWindowTitle();
  if (!window.Create(window_title, origin, size)) {
    return EXIT_FAILURE;
  }
  TrackWindowSize(window.GetHandle());
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
