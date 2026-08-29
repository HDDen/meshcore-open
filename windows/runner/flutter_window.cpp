#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT_PTR kFirstFrameTimerId = 1;
constexpr UINT kFirstFrameTimeoutMs = 15000;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterWindowActivationChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    ::KillTimer(GetHandle(), kFirstFrameTimerId);
    this->Show();
  });

  ::SetTimer(GetHandle(), kFirstFrameTimerId, kFirstFrameTimeoutMs, nullptr);

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterWindowActivationChannel() {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "meshcore_open/window_activation",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "restoreAndFocus") {
          RestoreAndFocus();
          result->Success();
          return;
        }
        result->NotImplemented();
      });

  window_activation_channel_ = std::move(channel);
}

void FlutterWindow::RestoreAndFocus() {
  HWND window = GetHandle();
  if (window == nullptr) {
    return;
  }

  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }
  ::BringWindowToTop(window);
  ::SetActiveWindow(window);
  ::SetForegroundWindow(window);
  ::SetFocus(window);
}

void FlutterWindow::OnDestroy() {
  ::KillTimer(GetHandle(), kFirstFrameTimerId);
  if (flutter_controller_) {
    window_activation_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_TIMER && wparam == kFirstFrameTimerId) {
    ::KillTimer(hwnd, kFirstFrameTimerId);
    Show();
    ::MessageBoxW(
        hwnd,
        L"Flutter did not render the first application frame within 15 "
        L"seconds.\n\nError code: MCO-WIN-STARTUP-001\n\nPlease "
        L"include this code when reporting the problem.",
        L"MCO Advanced startup error", MB_OK | MB_ICONERROR);
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
