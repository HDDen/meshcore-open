import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  // Preserve the native contract while adding scene-aware transitions.
  // These tests do not reproduce GPU corruption or require the injected dylib.
  func testPresentationBaselineKeepsOrderedIndependentSnapshots() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(applicationActive: true))
    defer { withExtendedLifetime(monitor) {} }

    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    let initial = try messenger.watch(PresentationTestMessenger.presentation)
    let activity = try messenger.watch(PresentationTestMessenger.activity)
    XCTAssertEqual(initial["schema"] as? Int, 1)
    XCTAssertNotNil(initial["enabled"] as? Bool)
    XCTAssertEqual(initial["source"] as? String, "initial")
    XCTAssertNotNil(initial["nativeAtUtcMs"] as? Int)
    XCTAssertNotNil(initial["nativeUptimeMs"] as? Int)
    XCTAssertEqual(initial["active"] as? Bool, true)
    XCTAssertEqual(initial["revision"] as? Int, activity["revision"] as? Int)
    let revision = try XCTUnwrap(initial["revision"] as? Int)

    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    let inactive = messenger.snapshots(PresentationTestMessenger.presentation)
    XCTAssertEqual(inactive.count, 1)
    XCTAssertEqual(inactive.first?["active"] as? Bool, false)
    XCTAssertEqual(inactive.first?["revision"] as? Int, revision + 1)

    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    for channel in [PresentationTestMessenger.presentation, PresentationTestMessenger.activity] {
      let snapshots = messenger.snapshots(channel)
      XCTAssertEqual(snapshots.compactMap { $0["active"] as? Bool }, [false, true])
      XCTAssertEqual(snapshots.compactMap { $0["revision"] as? Int }, [revision + 1, revision + 2])
    }
  }

  func testPresentationBaselineUnwatchKeepsActivitySubscriberAlive() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(applicationActive: true))
    defer { withExtendedLifetime(monitor) {} }

    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    _ = try messenger.watch(PresentationTestMessenger.presentation)
    _ = try messenger.watch(PresentationTestMessenger.activity)
    _ = try messenger.call(PresentationTestMessenger.presentation, method: "unwatch")
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertTrue(messenger.snapshots(PresentationTestMessenger.presentation).isEmpty)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.activity).last?["active"] as? Bool, false)

    // Re-subscribing returns the latest state, without replacing the other channel.
    let restored = try messenger.watch(PresentationTestMessenger.presentation)
    XCTAssertEqual(restored["active"] as? Bool, false)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.presentation).last?["active"] as? Bool, true)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.activity).count, 2)
  }

  func testPresentationBaselineReleasesChannelsAndObservers() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    var monitor: IosPresentationMonitor? = IosPresentationMonitor(
      binaryMessenger: messenger, notificationCenter: center)
    weak var released = monitor
    _ = try messenger.watch(PresentationTestMessenger.presentation)
    _ = try messenger.watch(PresentationTestMessenger.activity)
    monitor = nil
    XCTAssertNil(released)
    XCTAssertTrue(messenger.handlers.isEmpty)
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertTrue(messenger.events.isEmpty)
  }

  func testSceneInactivityCannotBeOverriddenByApplicationResume() {
    var activity = IosPresentationActivityState(applicationActive: true)
    activity.updateScene(identifier: "flutter", active: false)
    activity.applicationActive = false
    activity.applicationActive = true
    XCTAssertFalse(activity.active, "Application resume must not unlock an inactive scene")
    activity.updateScene(identifier: "flutter", active: true)
    XCTAssertTrue(activity.active)

    // Reverse activation order: an active scene must still wait for the app.
    activity.applicationActive = false
    activity.updateScene(identifier: "flutter", active: true)
    XCTAssertFalse(activity.active)
    activity.applicationActive = true
    XCTAssertTrue(activity.active)
  }

  func testUnrelatedSceneCannotUnlockPresentation() {
    var activity = IosPresentationActivityState(applicationActive: true)
    activity.updateScene(identifier: "flutter", active: false)
    activity.updateScene(identifier: "another-session", active: true)
    activity.disconnectScene(identifier: "another-session")
    XCTAssertFalse(activity.active)
    XCTAssertEqual(activity.sceneIdentifier, "flutter")
    activity.updateScene(identifier: "flutter", active: true)
    XCTAssertTrue(activity.active)
  }

  func testDisconnectedSceneWaitsForAnActiveReplacement() {
    var activity = IosPresentationActivityState(applicationActive: true)
    activity.updateScene(identifier: "old", active: true)
    activity.disconnectScene(identifier: "old")
    XCTAssertFalse(activity.active)
    activity.updateScene(identifier: "replacement", active: false)
    XCTAssertFalse(activity.active)
    activity.updateScene(identifier: "replacement", active: true)
    XCTAssertTrue(activity.active)
  }

  func testNativeSnapshotKeepsInactiveSceneAfterApplicationActivation() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(
        applicationActive: false, sceneIdentifier: "flutter", sceneActive: false))
    defer { withExtendedLifetime(monitor) {} }
    _ = try messenger.watch(PresentationTestMessenger.presentation)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    let snapshot = try messenger.watch(PresentationTestMessenger.presentation)
    XCTAssertEqual(snapshot["applicationActive"] as? Bool, true)
    XCTAssertEqual(snapshot["sceneActive"] as? Bool, false)
    XCTAssertEqual(snapshot["active"] as? Bool, false)
    XCTAssertTrue(messenger.events.isEmpty, "No positive transition is allowed yet")
  }

}

/// Exercise actual FlutterMethodChannel encoding without a live Dart isolate.
private final class PresentationTestMessenger: NSObject, FlutterBinaryMessenger {
  static let presentation = "mco_advanced/ios_presentation"
  static let activity = "mco_advanced/ios_activity"
  private let codec = FlutterStandardMethodCodec.sharedInstance()
  private var connection: FlutterBinaryMessengerConnection = 0
  private var connections: [FlutterBinaryMessengerConnection: String] = [:]
  private(set) var handlers: [String: FlutterBinaryMessageHandler] = [:]
  private(set) var events: [(String, FlutterMethodCall)] = []

  func send(onChannel channel: String, message: Data?) {
    if let message = message {
      events.append((channel, codec.decodeMethodCall(message)))
    }
  }

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    send(onChannel: channel, message: message)
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    connection += 1
    handlers[channel] = handler
    connections[connection] = channel
    return connection
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    if let channel = connections.removeValue(forKey: connection),
       !connections.contains(where: { $0.key > connection && $0.value == channel }) {
      handlers.removeValue(forKey: channel)
    }
  }

  func call(_ channel: String, method: String) throws -> Any? {
    let handler = try XCTUnwrap(handlers[channel])
    var reply: Data?
    var completed = false
    handler(codec.encodeMethodCall(FlutterMethodCall(methodName: method, arguments: nil))) {
      reply = $0
      completed = true
    }
    XCTAssertTrue(completed, "Native control replies must not require a running Dart isolate")
    return codec.decodeEnvelope(try XCTUnwrap(reply))
  }

  func watch(_ channel: String) throws -> [String: Any] {
    return try XCTUnwrap(try call(channel, method: "watch") as? [String: Any])
  }

  func snapshots(_ channel: String) -> [[String: Any]] {
    return events.filter { $0.0 == channel }.compactMap { $0.1.arguments as? [String: Any] }
  }
}
