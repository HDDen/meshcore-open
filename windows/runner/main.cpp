#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <algorithm>
#include <fstream>
#include <optional>
#include <string>
#include <string_view>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#ifndef FLUTTER_VERSION
#define FLUTTER_VERSION "1.0.0"
#endif

namespace {
constexpr std::wstring_view kDataDirArgument = L"--data-dir";
constexpr wchar_t kDefaultDataFolder[] = L"userdata";
constexpr wchar_t kWindowStateFile[] = L"window_state.txt";
// Where builds before the data folder kept the size: read until the data
// folder keeps it, then deleted together with the keys it leaves empty.
constexpr wchar_t kLegacyWindowStateRegKey[] =
    L"Software\\com.meshcore\\meshcore_open\\WindowState";
constexpr const wchar_t* kLegacyWindowStateRegKeys[] = {
    kLegacyWindowStateRegKey, L"Software\\com.meshcore\\meshcore_open",
    L"Software\\com.meshcore"};
constexpr wchar_t kLegacyWindowWidthRegValue[] = L"LogicalWidth";
constexpr wchar_t kLegacyWindowHeightRegValue[] = L"LogicalHeight";
constexpr unsigned int kDefaultWindowWidth = 1280;
constexpr unsigned int kDefaultWindowHeight = 720;
constexpr unsigned int kMinSavedWindowWidth = 320;
constexpr unsigned int kMinSavedWindowHeight = 240;
constexpr unsigned int kMaxSavedWindowSize = 32767;
WNDPROC g_original_window_proc = nullptr;
std::wstring g_window_state_file;
bool g_legacy_window_state_deleted = false;

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

bool IsSeparator(wchar_t character) {
  return character == L'\\' || character == L'/';
}

// The whitespace Dart's String.trim removes.
bool IsDartWhitespace(wchar_t character) {
  return (character >= 0x09 && character <= 0x0D) || character == 0x20 ||
         character == 0x85 || character == 0xA0 || character == 0x1680 ||
         (character >= 0x2000 && character <= 0x200A) ||
         character == 0x2028 || character == 0x2029 || character == 0x202F ||
         character == 0x205F || character == 0x3000 || character == 0xFEFF;
}

// Absolute the way package:path reads a Windows path: a drive letter with a
// separator, or a leading separator.
bool IsAbsolutePath(std::wstring_view path) {
  if (path.empty()) {
    return false;
  }
  if (IsSeparator(path[0])) {
    return true;
  }
  const wchar_t drive = path[0];
  return path.size() >= 3 &&
         ((drive >= L'A' && drive <= L'Z') ||
          (drive >= L'a' && drive <= L'z')) &&
         path[1] == L':' && IsSeparator(path[2]);
}

// The folder of this executable with its closing separator, empty when
// Windows does not say.
std::wstring ExecutableFolder() {
  std::wstring path(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (length == 0) {
      return std::wstring();
    }
    if (length < path.size()) {
      path.resize(length);
      break;
    }
    path.resize(path.size() * 2);
  }
  const size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? std::wstring()
                                         : path.substr(0, separator + 1);
}

// The data folder the Dart side opens, by the rules of selectDataRoot in
// lib/storage/data_root_core.dart: the last --data-dir wins, it is trimmed
// and stripped of quotes, a relative path counts from the executable's
// folder, and no argument means userdata beside the executable. Empty when
// --data-dir names no folder, which stops the app on an error screen.
std::wstring DataFolder() {
  const std::wstring app_folder = ExecutableFolder();
  if (app_folder.empty()) {
    return std::wstring();
  }

  std::optional<std::wstring> given;
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv != nullptr) {
    for (int i = 1; i < argc; i++) {
      const std::wstring_view argument = argv[i];
      if (argument == kDataDirArgument) {
        given.emplace();
      } else if (argument.size() > kDataDirArgument.size() &&
                 argument.compare(0, kDataDirArgument.size(),
                                  kDataDirArgument) == 0 &&
                 argument[kDataDirArgument.size()] == L'=') {
        given.emplace(argument.substr(kDataDirArgument.size() + 1));
      }
    }
    ::LocalFree(argv);
  }
  if (!given) {
    return app_folder + kDefaultDataFolder;
  }

  std::wstring& value = *given;
  const auto first =
      std::find_if_not(value.begin(), value.end(), IsDartWhitespace);
  const auto last =
      std::find_if_not(value.rbegin(), value.rend(), IsDartWhitespace).base();
  value = first < last ? std::wstring(first, last) : std::wstring();
  value.erase(std::remove(value.begin(), value.end(), L'"'), value.end());
  if (value.empty()) {
    return std::wstring();
  }
  return IsAbsolutePath(value) ? value : app_folder + value;
}

// window_state.txt in the data folder, empty when there is no data folder.
std::wstring WindowStateFile() {
  std::wstring path = DataFolder();
  if (path.empty()) {
    return path;
  }
  if (!IsSeparator(path.back())) {
    path.push_back(L'\\');
  }
  return path + kWindowStateFile;
}

bool ReadWindowStateFile(unsigned int& width, unsigned int& height) {
  if (g_window_state_file.empty()) {
    return false;
  }
  std::ifstream file(g_window_state_file.c_str());
  return static_cast<bool>(file >> width >> height);
}

DWORD ReadLegacyWindowSizeValue(const wchar_t* name, DWORD fallback) {
  DWORD value = fallback;
  DWORD value_size = sizeof(value);
  RegGetValue(HKEY_CURRENT_USER, kLegacyWindowStateRegKey, name,
              RRF_RT_REG_DWORD, nullptr, &value, &value_size);
  return value;
}

// The size kept in the data folder, else the one earlier builds kept in the
// registry, else the default.
Win32Window::Size LoadWindowSize() {
  unsigned int width = 0;
  unsigned int height = 0;
  if (!ReadWindowStateFile(width, height)) {
    width = ReadLegacyWindowSizeValue(kLegacyWindowWidthRegValue,
                                      kDefaultWindowWidth);
    height = ReadLegacyWindowSizeValue(kLegacyWindowHeightRegValue,
                                       kDefaultWindowHeight);
  }
  return Win32Window::Size(
      width >= kMinSavedWindowWidth && width <= kMaxSavedWindowSize
          ? width
          : kDefaultWindowWidth,
      height >= kMinSavedWindowHeight && height <= kMaxSavedWindowSize
          ? height
          : kDefaultWindowHeight);
}

bool DeleteEmptyKey(const wchar_t* path) {
  HKEY key;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, path, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  DWORD subkeys = 0;
  DWORD values = 0;
  const LSTATUS status =
      ::RegQueryInfoKeyW(key, nullptr, nullptr, nullptr, &subkeys, nullptr,
                         nullptr, &values, nullptr, nullptr, nullptr, nullptr);
  ::RegCloseKey(key);
  return status == ERROR_SUCCESS && subkeys == 0 && values == 0 &&
         ::RegDeleteKeyW(HKEY_CURRENT_USER, path) == ERROR_SUCCESS;
}

// Only the two values are ours: a key holding anything else stays.
void DeleteLegacyWindowState() {
  if (g_legacy_window_state_deleted) {
    return;
  }
  g_legacy_window_state_deleted = true;
  ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kLegacyWindowStateRegKey,
                       kLegacyWindowWidthRegValue);
  ::RegDeleteKeyValueW(HKEY_CURRENT_USER, kLegacyWindowStateRegKey,
                       kLegacyWindowHeightRegValue);
  for (const wchar_t* key : kLegacyWindowStateRegKeys) {
    if (!DeleteEmptyKey(key)) {
      break;
    }
  }
}

void SaveWindowSize(HWND window) {
  if (g_window_state_file.empty() || ::IsIconic(window)) {
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

  // The Dart side creates the data folder; until it exists the open fails
  // and nothing is kept.
  std::ofstream file(g_window_state_file.c_str());
  file << width << ' ' << height << '\n';
  file.close();
  if (file) {
    DeleteLegacyWindowState();
  }
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

  g_window_state_file = WindowStateFile();

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
