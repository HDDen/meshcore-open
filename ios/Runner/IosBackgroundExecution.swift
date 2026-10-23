import Flutter
import UIKit

extension Notification.Name {
  static let mcoIosExecutionCompatibilityChanged = Notification.Name("mco.ios.execution.compatibility")
}

/// Replaceable native backend; no private APIs in policy/channel/button code.
protocol IosBackgroundExecutionBackend: AnyObject {
  var audioRunning: Bool { get }
  func setArmed(_ armed: Bool) -> Bool
  func setBackground(_ background: Bool)
}

final class ImmortalizerExecutionBackend: IosBackgroundExecutionBackend {
  static func suppressesDiff(_ description: String) -> Bool {
    MCOImmortalizerSuppressesDiff(description)
  }
  static func defersDiff(_ description: String, background: Bool, transitioning: Bool) -> Bool {
    MCOImmortalizerShouldDeferDiff(description, background, transitioning)
  }
  var audioRunning: Bool { MCOImmortalizerAudioRunning() }
  func setArmed(_ armed: Bool) -> Bool { MCOImmortalizerSetArmed(armed) }
  func setBackground(_ background: Bool) { MCOImmortalizerSetBackground(background) }
}

/// Physical state is native-owned; Dart sends authorized TCP reasons only.
final class IosBackgroundExecutionController {
  static let manualAllowedKey = "mcoa.ios.execution.manualAllowed"
  private let backend: IosBackgroundExecutionBackend
  private let preferences: UserDefaults
  private let center: NotificationCenter
  private let legacyDetected: () -> Bool
  private var observers: [NSObjectProtocol] = []
  private var channels: [ObjectIdentifier: FlutterMethodChannel] = [:]
  private var viewController: () -> UIViewController? = { nil }
  private let button = IosBackgroundExecutionButton()
  private var closed = false
  private var stateRevision = 0
  private var lastState: [String: Bool]?
  private var foregroundVisible: Bool
  private(set) var background: Bool
  private(set) var eligible = false
  private(set) var manualAllowed: Bool
  private(set) var armed = false
  var compatibilityRequired: Bool { armed }

  init(backend: IosBackgroundExecutionBackend? = nil,
       preferences: UserDefaults = .standard,
       notificationCenter: NotificationCenter = .default,
       initialBackground: Bool? = nil,
       legacyDetected: @escaping () -> Bool = { MCOImmortalizerHasLegacyInjection() }) {
    self.backend = backend ?? ImmortalizerExecutionBackend()
    self.preferences = preferences
    self.center = notificationCenter
    self.legacyDetected = legacyDetected
    background = initialBackground ?? (UIApplication.shared.applicationState == .background)
    foregroundVisible = !background
    // A new independent preference: legacy "immortalized" does not control us.
    manualAllowed = preferences.object(forKey: Self.manualAllowedKey) as? Bool ?? true
    button.onToggle = { [weak self] in
      guard let self = self else { return }
      self.setManualAllowed(!self.manualAllowed)
    }
    observe(UIApplication.willResignActiveNotification) { $0.foregroundVisible = false }
    observe(UIApplication.didEnterBackgroundNotification) {
      $0.background = true
      $0.foregroundVisible = false
    }
    observe(UIApplication.willEnterForegroundNotification) {
      $0.background = false
      $0.foregroundVisible = false
    }
    observe(UIApplication.didBecomeActiveNotification) {
      $0.background = false
      $0.foregroundVisible = true
    }
    for (name, background, visible) in [
      (UIScene.willDeactivateNotification, false, false),
      (UIScene.didEnterBackgroundNotification, true, false),
      (UIScene.willEnterForegroundNotification, false, false),
      (UIScene.didActivateNotification, false, true)
    ] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
        guard let self = self, !self.closed,
              let scene = note.object as? UIWindowScene,
              scene === self.viewController()?.viewIfLoaded?.window?.windowScene else { return }
        // Deactivation alone is not background (e.g. Control Center).
        if name != UIScene.willDeactivateNotification { self.background = background }
        self.foregroundVisible = visible
        self.reconcile()
      })
    }
  }

  private func observe(_ name: Notification.Name,
                       change: @escaping (IosBackgroundExecutionController) -> Void) {
    observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      guard let self = self, !self.closed else { return }
      change(self)
      self.reconcile()
    })
  }

  func register(binaryMessenger: FlutterBinaryMessenger,
                viewController: @escaping () -> UIViewController?) {
    let identity = ObjectIdentifier(binaryMessenger as AnyObject)
    guard !closed, channels[identity] == nil else { return }
    self.viewController = viewController
    let channel = FlutterMethodChannel(name: "mco_advanced/ios_execution", binaryMessenger: binaryMessenger)
    channels[identity] = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, !self.closed else {
        result(FlutterError(code: "unavailable", message: "Execution controller unavailable", details: nil))
        return
      }
      switch call.method {
      case "configure":
        guard let arguments = call.arguments as? [String: Any],
              let eligible = arguments["eligible"] as? Bool else {
          result(FlutterError(code: "bad_args", message: "Expected eligibility", details: nil))
          return
        }
        self.configure(eligible: eligible)
        result(nil)
      case "status":
        result(["eligible": self.eligible, "manualAllowed": self.manualAllowed,
                "background": self.background, "armed": self.armed,
                "audioRunning": self.backend.audioRunning, "legacyInjection": self.legacyDetected()])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func configure(eligible: Bool) {
    guard !closed else { return }
    self.eligible = eligible
    reconcile(forceState: true)
  }

  func setManualAllowed(_ allowed: Bool) {
    guard !closed else { return }
    manualAllowed = allowed
    preferences.set(allowed, forKey: Self.manualAllowedKey)
    reconcile()
  }

  private func reconcile(forceState: Bool = false) {
    let desired = eligible && manualAllowed && !legacyDetected()
    if desired && !armed {
      // Publish compatibility before enabling hooks/audio in an inactive scene.
      armed = true
      center.post(name: .mcoIosExecutionCompatibilityChanged, object: nil)
      if !backend.setArmed(true) {
        armed = false
        center.post(name: .mcoIosExecutionCompatibilityChanged, object: nil)
        NSLog("[iOSExecution] Backend unavailable; no embedded hold started")
      }
    } else if !desired && armed {
      _ = backend.setArmed(false)
      armed = false
      center.post(name: .mcoIosExecutionCompatibilityChanged, object: nil)
    }
    // No audio/timer in foreground, including Control Center deactivation.
    backend.setBackground(background && armed)
    button.update(host: viewController(), visible: eligible && foregroundVisible && !legacyDetected(),
                  selected: manualAllowed)
    let state = ["eligible": eligible, "manualAllowed": manualAllowed, "background": background,
                 "armed": armed, "audioRunning": backend.audioRunning, "legacyInjection": legacyDetected()]
    if forceState || state != lastState {
      lastState = state
      stateRevision += 1
      var snapshot: [String: Any] = state.reduce(into: [:]) { $0[$1.key] = $1.value }
      snapshot["schema"] = 1
      snapshot["revision"] = stateRevision
      for channel in channels.values { channel.invokeMethod("state", arguments: snapshot) }
      NSLog("[iOSExecution] eligible=%d manual=%d background=%d armed=%d audio=%d legacy=%d",
            eligible ? 1 : 0, manualAllowed ? 1 : 0, background ? 1 : 0,
            armed ? 1 : 0, backend.audioRunning ? 1 : 0, legacyDetected() ? 1 : 0)
    }
  }

  func close() {
    guard !closed else { return }
    closed = true
    for observer in observers { center.removeObserver(observer) }
    observers.removeAll()
    for channel in channels.values { channel.setMethodCallHandler(nil) }
    channels.removeAll()
    _ = backend.setArmed(false)
    backend.setBackground(false)
    let wasArmed = armed
    armed = false
    button.close()
    if wasArmed { center.post(name: .mcoIosExecutionCompatibilityChanged, object: nil) }
  }

  deinit { close() }
}
