#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowChannelName[] = "com.loriek.onlystream/window";

int ParseResizeHitTest(const std::string& edge) {
  if (edge == "top") return HTTOP;
  if (edge == "bottom") return HTBOTTOM;
  if (edge == "left") return HTLEFT;
  if (edge == "right") return HTRIGHT;
  if (edge == "topLeft") return HTTOPLEFT;
  if (edge == "topRight") return HTTOPRIGHT;
  if (edge == "bottomLeft") return HTBOTTOMLEFT;
  if (edge == "bottomRight") return HTBOTTOMRIGHT;
  return 0;
}

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
  SetupWindowChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (window_channel_) {
    window_channel_->SetMethodCallHandler(nullptr);
    window_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

flutter::EncodableMap FlutterWindow::BuildWindowStateMap() const {
  return flutter::EncodableMap{
      {flutter::EncodableValue("isMaximized"),
       flutter::EncodableValue(IsMaximized())},
      {flutter::EncodableValue("isFullscreen"),
       flutter::EncodableValue(IsFullscreen())},
      {flutter::EncodableValue("isFocused"),
       flutter::EncodableValue(IsFocused())},
  };
}

void FlutterWindow::OnWindowStateChanged() {
  if (!window_channel_) {
    return;
  }
  window_channel_->InvokeMethod(
      "onWindowStateChanged",
      std::make_unique<flutter::EncodableValue>(BuildWindowStateMap()));
}

void FlutterWindow::SetupWindowChannel() {
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), kWindowChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "getWindowState") {
          result->Success(flutter::EncodableValue(BuildWindowStateMap()));
          return;
        }
        if (method == "minimize") {
          MinimizeWindow();
          result->Success();
          return;
        }
        if (method == "maximize") {
          MaximizeWindow();
          result->Success();
          return;
        }
        if (method == "unmaximize") {
          UnmaximizeWindow();
          result->Success();
          return;
        }
        if (method == "setFullscreen") {
          bool fullscreen = false;
          if (const auto* flag = std::get_if<bool>(call.arguments())) {
            fullscreen = *flag;
          } else if (const auto* map =
                         std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = map->find(flutter::EncodableValue("fullscreen"));
            if (it != map->end()) {
              if (const auto* mapped_flag = std::get_if<bool>(&it->second)) {
                fullscreen = *mapped_flag;
              }
            }
          }
          SetFullscreen(fullscreen);
          result->Success();
          return;
        }
        if (method == "close") {
          CloseWindow();
          result->Success();
          return;
        }
        if (method == "startDragging") {
          StartDragging();
          result->Success();
          return;
        }
        if (method == "startResizing") {
          std::string edge;
          if (const auto* str = std::get_if<std::string>(call.arguments())) {
            edge = *str;
          } else if (const auto* map =
                         std::get_if<flutter::EncodableMap>(call.arguments())) {
            auto it = map->find(flutter::EncodableValue("edge"));
            if (it != map->end()) {
              if (const auto* mapped_edge =
                      std::get_if<std::string>(&it->second)) {
                edge = *mapped_edge;
              }
            }
          }
          const int hit_test = ParseResizeHitTest(edge);
          if (hit_test != 0) {
            StartResizing(hit_test);
          }
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
