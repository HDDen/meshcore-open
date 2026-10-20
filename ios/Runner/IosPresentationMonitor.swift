import Flutter
import UIKit

/// Observe native transitions directly; do not swizzle UIKit or change Dart's
/// lifecycle. The compatibility guard is inert without the injected UI class.
final class IosPresentationMonitor {
  private let channel: FlutterMethodChannel
  private let activityChannel: FlutterMethodChannel
  private var watchingActivity = false
  private var observers: [NSObjectProtocol] = []
  private var watching = false
  private var active: Bool
  private var revision = 0

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "mco_advanced/ios_presentation",
      binaryMessenger: binaryMessenger
    )
    // Independent activity subscribers must not replace the rendering handler.
    activityChannel = FlutterMethodChannel(
      name: "mco_advanced/ios_activity",
      binaryMessenger: binaryMessenger
    )
    active = UIApplication.shared.applicationState == .active
    let center = NotificationCenter.default
    // Stop before background GPU access is revoked; resume only on didBecomeActive.
    for name in [UIApplication.willResignActiveNotification,
                 UIApplication.didEnterBackgroundNotification,
                 UIApplication.willEnterForegroundNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] _ in self?.update(active: false)
      })
    }
    observers.append(center.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.update(active: true) })
    activityChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Activity monitor unavailable", details: nil))
        return
      }
      switch call.method {
      case "watch":
        self.watchingActivity = true
        result(self.activitySnapshot())
      case "unwatch":
        self.watchingActivity = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Presentation monitor unavailable", details: nil))
        return
      }
      switch call.method {
      case "watch":
        self.watching = true
        result(self.snapshot())
      case "unwatch":
        self.watching = false
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func activitySnapshot() -> [String: Any] {
    return ["schema": 1, "active": active, "revision": revision]
  }

  private func snapshot() -> [String: Any] {
    // v3's applicationState hook also runs with its toggle off. Detect the
    // loaded class, not the preference, without invoking third-party methods.
    return ["schema": 1, "enabled": NSClassFromString("FloatingButtonWindow") != nil,
            "active": active, "revision": revision]
  }

  private func update(active: Bool) {
    guard self.active != active else { return }
    self.active = active
    revision += 1
    if watchingActivity {
      activityChannel.invokeMethod("activity", arguments: activitySnapshot())
    }
    if watching {
      channel.invokeMethod("presentation", arguments: snapshot())
    }
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    channel.setMethodCallHandler(nil)
    activityChannel.setMethodCallHandler(nil)
  }
}
