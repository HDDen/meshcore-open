import Flutter
import UIKit

/// A positive application event must not override an inactive Flutter scene.
/// Keep this independent of UIKit so notification orderings can be tested.
struct IosPresentationActivityState {
  var applicationActive: Bool
  private(set) var sceneIdentifier: String?
  private(set) var sceneActive: Bool?

  init(applicationActive: Bool, sceneIdentifier: String? = nil, sceneActive: Bool? = nil) {
    self.applicationActive = applicationActive
    self.sceneIdentifier = sceneIdentifier
    self.sceneActive = sceneActive
  }

  var active: Bool { applicationActive && sceneActive != false }

  mutating func updateScene(identifier: String, active: Bool) {
    // Runner currently supports one application scene. Ignore other sessions.
    guard sceneIdentifier == nil || sceneIdentifier == identifier else { return }
    sceneIdentifier = identifier
    sceneActive = active
  }

  mutating func disconnectScene(identifier: String) {
    guard sceneIdentifier == identifier else { return }
    sceneIdentifier = nil
    // Remain paused until the replacement scene actually becomes active.
    sceneActive = false
  }
}

/// Observe native transitions directly; do not swizzle UIKit or change Dart's
/// lifecycle. The compatibility guard is inert without the injected UI class.
final class IosPresentationMonitor {
  private let channel: FlutterMethodChannel
  private let activityChannel: FlutterMethodChannel
  private let notificationCenter: NotificationCenter
  private var watchingActivity = false
  private var observers: [NSObjectProtocol] = []
  private var watching = false
  private var activity: IosPresentationActivityState
  private var revision = 0
  private var source = "initial"
  private var nativeAtUtcMs = Int64(Date().timeIntervalSince1970 * 1000)
  private var nativeUptimeMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)

  init(binaryMessenger: FlutterBinaryMessenger,
       notificationCenter: NotificationCenter = .default,
       initialActivity: IosPresentationActivityState? = nil) {
    // An isolated center lets native tests exercise notifications without
    // sending synthetic lifecycle changes to the running Flutter host.
    self.notificationCenter = notificationCenter
    channel = FlutterMethodChannel(
      name: "mco_advanced/ios_presentation",
      binaryMessenger: binaryMessenger
    )
    // Independent activity subscribers must not replace the rendering handler.
    activityChannel = FlutterMethodChannel(
      name: "mco_advanced/ios_activity",
      binaryMessenger: binaryMessenger
    )
    activity = initialActivity ?? Self.initialActivity()
    // Preserve the application fallback for older/non-scene runners.
    for (name, active, source) in [
      (UIApplication.willResignActiveNotification, false, "application.willResignActive"),
      (UIApplication.didEnterBackgroundNotification, false, "application.didEnterBackground"),
      (UIApplication.willEnterForegroundNotification, false, "application.willEnterForeground"),
      (UIApplication.didBecomeActiveNotification, true, "application.didBecomeActive")
    ] {
      observe(name, source: source) { monitor, _ in
        monitor.activity.applicationActive = active
      }
    }
    // Scene notifications arrive before/independently of the application
    // notifications that a background-execution tweak may interfere with.
    for (name, active, source) in [
      (UIScene.willDeactivateNotification, false, "scene.willDeactivate"),
      (UIScene.didEnterBackgroundNotification, false, "scene.didEnterBackground"),
      (UIScene.willEnterForegroundNotification, false, "scene.willEnterForeground"),
      (UIScene.didActivateNotification, true, "scene.didActivate")
    ] {
      observe(name, source: source) { monitor, notification in
        guard let scene = notification.object as? UIWindowScene,
              scene.session.role == .windowApplication else { return }
        monitor.activity.updateScene(identifier: scene.session.persistentIdentifier, active: active)
      }
    }
    observe(UIScene.didDisconnectNotification, source: "scene.didDisconnect") { monitor, notification in
      guard let scene = notification.object as? UIWindowScene else { return }
      monitor.activity.disconnectScene(identifier: scene.session.persistentIdentifier)
    }
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

  private static func initialActivity() -> IosPresentationActivityState {
    // A scene state is not the application's hooked applicationState getter.
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.session.role == .windowApplication }
      .sorted { $0.session.persistentIdentifier < $1.session.persistentIdentifier }
      .first
    return IosPresentationActivityState(
      applicationActive: UIApplication.shared.applicationState == .active,
      sceneIdentifier: scene?.session.persistentIdentifier,
      sceneActive: scene.map { $0.activationState == .foregroundActive }
    )
  }

  private func observe(_ name: Notification.Name, source: String,
                       change: @escaping (IosPresentationMonitor, Notification) -> Void) {
    // Timestamp at native receipt, not when Dart eventually drains its queue.
    observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: nil) {
      [weak self] notification in
      let utcMs = Int64(Date().timeIntervalSince1970 * 1000)
      let uptimeMs = Int64(ProcessInfo.processInfo.systemUptime * 1000)
      let apply = { [weak self] in
        guard let self = self else { return }
        let wasActive = self.activity.active
        change(self, notification)
        self.publishIfChanged(wasActive: wasActive, source: source,
                              utcMs: utcMs, uptimeMs: uptimeMs)
      }
      if Thread.isMainThread {
        apply()
      } else {
        DispatchQueue.main.async(execute: apply)
      }
    })
  }

  private func activitySnapshot() -> [String: Any] {
    return ["schema": 1, "active": activity.active, "revision": revision,
            "source": source, "nativeAtUtcMs": nativeAtUtcMs, "nativeUptimeMs": nativeUptimeMs,
            "applicationActive": activity.applicationActive,
            "sceneActive": activity.sceneActive.map { $0 as Any } ?? NSNull()]
  }

  private func snapshot() -> [String: Any] {
    // v3's applicationState hook also runs with its toggle off. Detect the
    // loaded class, not the preference, without invoking third-party methods.
    var snapshot = activitySnapshot()
    snapshot["enabled"] = NSClassFromString("FloatingButtonWindow") != nil
    return snapshot
  }

  private func publishIfChanged(wasActive: Bool, source: String, utcMs: Int64, uptimeMs: Int64) {
    guard wasActive != activity.active else { return }
    self.source = source
    nativeAtUtcMs = utcMs
    nativeUptimeMs = uptimeMs
    revision += 1
    if watchingActivity {
      activityChannel.invokeMethod("activity", arguments: activitySnapshot())
    }
    if watching {
      channel.invokeMethod("presentation", arguments: snapshot())
    }
  }

  deinit {
    for observer in observers { notificationCenter.removeObserver(observer) }
    channel.setMethodCallHandler(nil)
    activityChannel.setMethodCallHandler(nil)
  }
}
