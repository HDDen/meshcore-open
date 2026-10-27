import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  // Только публичный native API: этот engine не запускает Dart entrypoint.
  // Продолжение работающего Dart и отсутствие glyph corruption здесь не проверяются.
  func testGpuAvailabilityBaselineFlagDoesNotStartDartOrReplaceMessenger() {
    let engine = FlutterEngine(name: "mco_gpu_baseline", project: nil,
      allowHeadlessExecution: true)
    let other = FlutterEngine(name: "mco_gpu_baseline_other", project: nil,
      allowHeadlessExecution: true)
    let messenger = engine.binaryMessenger
    let otherGpuDisabled = other.isGpuDisabled
    XCTAssertNil(engine.isolateId)

    engine.isGpuDisabled = true
    XCTAssertTrue(engine.isGpuDisabled)
    XCTAssertNil(engine.isolateId)
    XCTAssertTrue((engine.binaryMessenger as AnyObject) === (messenger as AnyObject))
    XCTAssertEqual(other.isGpuDisabled, otherGpuDisabled)

    engine.isGpuDisabled = false
    XCTAssertFalse(engine.isGpuDisabled)
    XCTAssertNil(engine.isolateId)
    XCTAssertTrue((engine.binaryMessenger as AnyObject) === (messenger as AnyObject))
    XCTAssertEqual(other.isGpuDisabled, otherGpuDisabled)
  }

  // Native activity должна накапливаться и до подписки/обработки событий Dart.
  func testPresentationBaselineKeepsPhysicalStateWithoutSubscribers() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(applicationActive: true))
    defer { withExtendedLifetime(monitor) {} }

    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    XCTAssertTrue(messenger.events.isEmpty)

    for channel in [PresentationTestMessenger.presentation, PresentationTestMessenger.activity] {
      let snapshot = try messenger.watch(channel)
      XCTAssertEqual(snapshot["active"] as? Bool, false)
      XCTAssertEqual(snapshot["revision"] as? Int, 1)
      XCTAssertEqual(snapshot["source"] as? String, "application.willResignActive")
    }
    XCTAssertTrue(messenger.events.isEmpty)

    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    for channel in [PresentationTestMessenger.presentation, PresentationTestMessenger.activity] {
      let snapshots = messenger.snapshots(channel)
      XCTAssertEqual(snapshots.compactMap { $0["active"] as? Bool }, [true])
      XCTAssertEqual(snapshots.compactMap { $0["revision"] as? Int }, [2])
    }
  }

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

  func testNativeGpuGuardUsesPublicEngineWithoutStartingDart() {
    let engine = FlutterEngine(name: "mco_gpu_guard", project: nil, allowHeadlessExecution: true)
    engine.isGpuDisabled = false
    let messenger = engine.binaryMessenger
    let queue = GpuRecheckQueue()
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { engine },
      scheduleRecheck: queue.schedule)
    gpuGuard.update(enabled: true, active: false)
    XCTAssertTrue(engine.isGpuDisabled)
    XCTAssertNil(engine.isolateId)
    gpuGuard.update(enabled: true, active: true)
    queue.drain()
    XCTAssertFalse(engine.isGpuDisabled)
    XCTAssertNil(engine.isolateId)
    XCTAssertTrue((engine.binaryMessenger as AnyObject) === (messenger as AnyObject))
  }

  func testNativeGpuGuardPrecedesDartDeliveryAndRechecksFlutterForegroundWrite() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let target = GpuTestTarget()
    let queue = GpuRecheckQueue()
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { target },
      scheduleRecheck: queue.schedule)
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(applicationActive: true),
      gpuGuard: gpuGuard, compatibilityEnabled: { true })
    defer { withExtendedLifetime(monitor) {} }
    let initial = try messenger.watch(PresentationTestMessenger.presentation)
    XCTAssertEqual(initial["nativeGpuGuard"] as? Bool, true)
    XCTAssertEqual(initial["gpuDisabled"] as? Bool, false)

    // Не вызываем Dart handler: запрет должен быть установлен ещё на native.
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertTrue(target.isGpuDisabled)
    let inactive = try XCTUnwrap(messenger.snapshots(PresentationTestMessenger.presentation).last)
    XCTAssertEqual(inactive["active"] as? Bool, false)
    XCTAssertEqual(inactive["gpuDisabled"] as? Bool, true)
    queue.drain()

    // Первый порядок: Flutter снимает запрет до нашего обработчика.
    target.isGpuDisabled = false
    center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    XCTAssertTrue(target.isGpuDisabled)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.presentation).count, 1)
    // Второй порядок: Flutter снимает запрет после нашего обработчика.
    target.isGpuDisabled = false
    queue.drain()
    XCTAssertTrue(target.isGpuDisabled)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.presentation).count, 1)

    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertFalse(target.isGpuDisabled)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.presentation).last?["gpuDisabled"]
      as? Bool, false)
  }

  func testNativeGpuGuardWaitsForKnownInactiveSceneOnApplicationResume() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let target = GpuTestTarget()
    let queue = GpuRecheckQueue()
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { target },
      scheduleRecheck: queue.schedule)
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(
        applicationActive: false, sceneIdentifier: "flutter", sceneActive: false),
      gpuGuard: gpuGuard, compatibilityEnabled: { true })
    defer { withExtendedLifetime(monitor) {} }
    _ = try messenger.watch(PresentationTestMessenger.presentation)
    XCTAssertTrue(target.isGpuDisabled)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    queue.drain()
    XCTAssertTrue(target.isGpuDisabled)
    XCTAssertTrue(messenger.events.isEmpty)
  }

  func testNativeGpuGuardDoesNotArmForActivitySubscriberOrMissingCompatibility() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let target = GpuTestTarget()
    let queue = GpuRecheckQueue()
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { target },
      scheduleRecheck: queue.schedule)
    var compatibility = true
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(applicationActive: true),
      gpuGuard: gpuGuard, compatibilityEnabled: { compatibility })
    defer { withExtendedLifetime(monitor) {} }
    // Нет watch presentation, как при MCO_IOS_RENDER_GUARD=false.
    _ = try messenger.watch(PresentationTestMessenger.activity)
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertFalse(target.isGpuDisabled)
    XCTAssertTrue(queue.pending.isEmpty)

    compatibility = false
    let snapshot = try messenger.watch(PresentationTestMessenger.presentation)
    XCTAssertEqual(snapshot["nativeGpuGuard"] as? Bool, false)
    center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertFalse(target.isGpuDisabled)
    XCTAssertTrue(target.writes.isEmpty)
    XCTAssertTrue(queue.pending.isEmpty)
  }

  func testNativeGpuGuardUnwatchDefersReleaseUntilActiveAndKeepsActivitySubscriber() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let target = GpuTestTarget()
    let queue = GpuRecheckQueue()
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { target },
      scheduleRecheck: queue.schedule)
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(applicationActive: true),
      gpuGuard: gpuGuard, compatibilityEnabled: { true })
    defer { withExtendedLifetime(monitor) {} }
    _ = try messenger.watch(PresentationTestMessenger.presentation)
    _ = try messenger.watch(PresentationTestMessenger.activity)
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    _ = try messenger.call(PresentationTestMessenger.presentation, method: "unwatch")
    queue.drain()
    XCTAssertTrue(target.isGpuDisabled, "Не включаем GPU в фоне при отписке")
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertFalse(target.isGpuDisabled)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.presentation).count, 1)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.activity)
      .compactMap { $0["active"] as? Bool }, [false, true])
  }

  func testNativeGpuGuardIgnoresStaleRechecksAndRepeatedWrites() {
    let target = GpuTestTarget()
    let queue = GpuRecheckQueue()
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { target },
      scheduleRecheck: queue.schedule)
    gpuGuard.update(enabled: true, active: false)
    gpuGuard.update(enabled: true, active: false)
    XCTAssertEqual(target.writes, [true])
    gpuGuard.update(enabled: true, active: true)
    queue.drain()
    XCTAssertEqual(target.writes, [true, false])
    XCTAssertFalse(target.isGpuDisabled)
  }

  func testNativeGpuGuardDoesNotReleaseRestrictionItDidNotAcquire() {
    let target = GpuTestTarget(disabled: true)
    let queue = GpuRecheckQueue()
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { target },
      scheduleRecheck: queue.schedule)
    gpuGuard.update(enabled: true, active: true)
    gpuGuard.update(enabled: true, active: false)
    gpuGuard.update(enabled: true, active: true)
    queue.drain()
    gpuGuard.close()
    XCTAssertTrue(target.isGpuDisabled)
    XCTAssertTrue(target.writes.isEmpty)
  }

  func testNativeGpuGuardResolvesEngineAfterRegistrationAndReportsMissingTarget() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let target = GpuTestTarget()
    let queue = GpuRecheckQueue()
    var ready = false
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { ready ? target : nil },
      scheduleRecheck: queue.schedule)
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(applicationActive: false),
      gpuGuard: gpuGuard, compatibilityEnabled: { true })
    defer { withExtendedLifetime(monitor) {} }
    let unavailable = try messenger.watch(PresentationTestMessenger.presentation)
    XCTAssertEqual(unavailable["nativeGpuGuard"] as? Bool, false)
    XCTAssertTrue(unavailable["gpuDisabled"] is NSNull)
    ready = true
    queue.drain()
    XCTAssertTrue(target.isGpuDisabled)
    let available = try messenger.watch(PresentationTestMessenger.presentation)
    XCTAssertEqual(available["nativeGpuGuard"] as? Bool, true)
    XCTAssertEqual(available["gpuDisabled"] as? Bool, true)
    center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertFalse(target.isGpuDisabled)
  }

  func testNativeGpuGuardKeepsEngineIdentityAndCancelsQueuedWorkAfterClose() {
    let first = GpuTestTarget()
    let second = GpuTestTarget()
    let unrelated = GpuTestTarget()
    let queue = GpuRecheckQueue()
    var current = first
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { current },
      scheduleRecheck: queue.schedule)
    gpuGuard.update(enabled: true, active: false)
    current = second
    gpuGuard.update(enabled: true, active: false)
    XCTAssertTrue(first.isGpuDisabled)
    XCTAssertFalse(second.isGpuDisabled, "Guard остаётся привязан к первому живому engine")
    XCTAssertTrue(second.writes.isEmpty)
    gpuGuard.close()
    first.isGpuDisabled = false
    queue.drain()
    XCTAssertFalse(first.isGpuDisabled)
    XCTAssertTrue(unrelated.writes.isEmpty)
    gpuGuard.update(enabled: false, active: true)
    XCTAssertFalse(second.isGpuDisabled)
  }

  func testNativeGpuGuardAndMonitorReleaseWithoutQueuedRetainCycle() throws {
    let center = NotificationCenter()
    let messenger = PresentationTestMessenger()
    let target = GpuTestTarget()
    let queue = GpuRecheckQueue()
    var gpuGuard: IosPresentationGpuGuard? = IosPresentationGpuGuard(targetProvider: { target },
      scheduleRecheck: queue.schedule)
    weak var releasedGuard = gpuGuard
    var monitor: IosPresentationMonitor? = IosPresentationMonitor(
      binaryMessenger: messenger, notificationCenter: center,
      initialActivity: IosPresentationActivityState(applicationActive: true),
      gpuGuard: gpuGuard, compatibilityEnabled: { true })
    weak var releasedMonitor = monitor
    _ = try messenger.watch(PresentationTestMessenger.presentation)
    center.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertTrue(target.isGpuDisabled)
    monitor = nil
    gpuGuard = nil
    XCTAssertNil(releasedMonitor)
    XCTAssertNil(releasedGuard)
    XCTAssertTrue(messenger.handlers.isEmpty)
    target.isGpuDisabled = false
    queue.drain()
    XCTAssertFalse(target.isGpuDisabled)
  }
  private func executionFixture(background: Bool = false) -> (
    controller: IosBackgroundExecutionController, backend: ExecutionTestBackend,
    preferences: UserDefaults, center: NotificationCenter
  ) {
    let name = "mco.execution.tests.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: name)!
    let backend = ExecutionTestBackend()
    let center = NotificationCenter()
    let controller = IosBackgroundExecutionController(backend: backend, preferences: preferences,
      notificationCenter: center, initialBackground: background, legacyDetected: { false })
    addTeardownBlock {
      controller.close()
      preferences.removePersistentDomain(forName: name)
    }
    return (controller, backend, preferences, center)
  }

  func testExecutionAudioOnlyInPhysicalBackgroundNotInactiveOrForeground() {
    let f = executionFixture()
    f.controller.configure(eligible: true)
    XCTAssertTrue(f.controller.armed)
    XCTAssertFalse(f.backend.audioRunning)
    f.center.post(name: UIApplication.willResignActiveNotification, object: nil)
    XCTAssertFalse(f.backend.audioRunning)
    f.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    f.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertTrue(f.backend.audioRunning)
    XCTAssertEqual(f.backend.audioStarts, 1)
    f.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    XCTAssertFalse(f.backend.audioRunning)
    XCTAssertEqual(f.backend.audioStops, 1)
    f.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertTrue(f.controller.armed)
    XCTAssertFalse(f.backend.audioRunning)
  }

  func testExecutionNoEligibilityNeverArmsEvenInBackground() {
    let f = executionFixture(background: true)
    f.controller.configure(eligible: false)
    f.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertTrue(f.backend.armRequests.isEmpty)
    XCTAssertFalse(f.backend.audioRunning)
    XCTAssertFalse(f.controller.compatibilityRequired)
  }

  func testExecutionManualOffSurvivesSettingsAndControllerRestartUntilManualOn() {
    let f = executionFixture(background: true)
    f.controller.configure(eligible: true)
    XCTAssertTrue(f.backend.audioRunning)
    f.controller.setManualAllowed(false)
    f.controller.configure(eligible: false)
    f.controller.configure(eligible: true)
    XCTAssertFalse(f.backend.audioRunning)
    XCTAssertFalse(f.controller.manualAllowed)
    f.controller.close()
    let nextBackend = ExecutionTestBackend()
    let next = IosBackgroundExecutionController(backend: nextBackend, preferences: f.preferences,
      notificationCenter: f.center, initialBackground: true, legacyDetected: { false })
    defer { next.close() }
    next.configure(eligible: true)
    XCTAssertFalse(next.manualAllowed)
    XCTAssertFalse(nextBackend.audioRunning)
    next.setManualAllowed(true)
    XCTAssertTrue(nextBackend.audioRunning)
    next.configure(eligible: false)
    XCTAssertFalse(nextBackend.audioRunning)
    XCTAssertTrue(next.manualAllowed)
  }

  func testExecutionRefusesASecondBackendOverLegacyInjection() {
    let f = executionFixture(background: true)
    let backend = ExecutionTestBackend()
    let controller = IosBackgroundExecutionController(backend: backend, preferences: f.preferences,
      notificationCenter: f.center, initialBackground: true, legacyDetected: { true })
    defer { controller.close() }
    controller.configure(eligible: true)
    XCTAssertTrue(backend.armRequests.isEmpty)
    XCTAssertFalse(backend.audioRunning)
    XCTAssertFalse(controller.compatibilityRequired)
  }

  func testExecutionUnavailableBackendDoesNotClaimArmedOrRunning() {
    let f = executionFixture(background: true)
    f.backend.canArm = false
    f.controller.configure(eligible: true)
    XCTAssertFalse(f.controller.armed)
    XCTAssertFalse(f.backend.audioRunning)
    XCTAssertFalse(f.controller.compatibilityRequired)
  }

  func testExecutionCompatibilityPublishesBeforeActivationAndKeepsPhysicalState() throws {
    let f = executionFixture(background: true)
    let messenger = PresentationTestMessenger()
    let target = GpuTestTarget()
    let queue = GpuRecheckQueue()
    let gpuGuard = IosPresentationGpuGuard(targetProvider: { target }, scheduleRecheck: queue.schedule)
    let monitor = IosPresentationMonitor(binaryMessenger: messenger, notificationCenter: f.center,
      initialActivity: IosPresentationActivityState(applicationActive: false),
      gpuGuard: gpuGuard, compatibilityEnabled: { f.controller.compatibilityRequired })
    defer { withExtendedLifetime(monitor) {} }
    _ = try messenger.watch(PresentationTestMessenger.presentation)
    f.backend.onArm = { armed in if armed { XCTAssertTrue(target.isGpuDisabled) } }
    f.controller.configure(eligible: true)
    let enabled = try XCTUnwrap(messenger.snapshots(PresentationTestMessenger.presentation).last)
    XCTAssertEqual(enabled["enabled"] as? Bool, true)
    XCTAssertEqual(enabled["active"] as? Bool, false)
    f.controller.configure(eligible: false)
    let disabled = try XCTUnwrap(messenger.snapshots(PresentationTestMessenger.presentation).last)
    XCTAssertEqual(disabled["enabled"] as? Bool, true) // Drain compatibility until physical resume.
    XCTAssertEqual(disabled["active"] as? Bool, false)
    XCTAssertGreaterThan(try XCTUnwrap(disabled["revision"] as? Int), try XCTUnwrap(enabled["revision"] as? Int))
    XCTAssertTrue(target.isGpuDisabled) // No GPU release in an inactive scene.
    f.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
    XCTAssertFalse(target.isGpuDisabled)
    XCTAssertEqual(messenger.snapshots(PresentationTestMessenger.presentation).last?["enabled"] as? Bool, false)
  }

  func testExecutionChannelUsesOnlyEligibilityAndCloseRevokesWithoutClearingPreference() throws {
    let f = executionFixture(background: true)
    let messenger = PresentationTestMessenger()
    f.controller.register(binaryMessenger: messenger, viewController: { nil })
    _ = try messenger.call("mco_advanced/ios_execution", method: "configure", arguments: ["eligible": true])
    XCTAssertTrue(f.backend.audioRunning)
    let status = try XCTUnwrap(try messenger.call("mco_advanced/ios_execution", method: "status") as? [String: Any])
    XCTAssertEqual(status["audioRunning"] as? Bool, true)
    f.controller.setManualAllowed(false)
    f.controller.close()
    f.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertFalse(f.backend.audioRunning)
    XCTAssertEqual(f.preferences.object(forKey: IosBackgroundExecutionController.manualAllowedKey) as? Bool, false)
    XCTAssertNil(messenger.handlers["mco_advanced/ios_execution"])
  }

  func testExecutionDiagnosticsRequestsNeverChangeHoldOrPreference() throws {
    let f = executionFixture(background: true)
    let messenger = PresentationTestMessenger()
    f.controller.register(binaryMessenger: messenger, viewController: { nil })
    let previousRequests = f.backend.armRequests
    let previousPreference = f.preferences.object(forKey: IosBackgroundExecutionController.manualAllowedKey) as? Bool
    let first = try XCTUnwrap(try messenger.call("mco_advanced/ios_execution", method: "diagnostics") as? [String: Any])
    let second = try XCTUnwrap(try messenger.call("mco_advanced/ios_execution", method: "diagnostics") as? [String: Any])
    XCTAssertEqual(first["source"] as? String, "requested")
    XCTAssertEqual((first["audio"] as? [String: Any])?["sampleRate"] as? Double, 48000)
    XCTAssertGreaterThan(try XCTUnwrap(second["revision"] as? Int), try XCTUnwrap(first["revision"] as? Int))
    XCTAssertEqual(f.backend.armRequests, previousRequests)
    XCTAssertEqual(f.backend.audioStarts, 0)
    XCTAssertFalse(f.controller.armed)
    XCTAssertEqual(f.preferences.object(forKey: IosBackgroundExecutionController.manualAllowedKey) as? Bool, previousPreference)
  }

  func testExecutionAudioEventsPublishDiagnosticsWithoutReconciliationAndStopAfterClose() {
    let f = executionFixture()
    let messenger = PresentationTestMessenger()
    f.controller.register(binaryMessenger: messenger, viewController: { nil })
    f.controller.configure(eligible: true)
    let requests = f.backend.armRequests
    f.center.post(name: .mcoIosExecutionAudioDiagnosticsChanged, object: nil)
    let events = messenger.events.filter { $0.1.method == "diagnostics" }
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(f.backend.armRequests, requests)
    XCTAssertFalse(f.backend.audioRunning)
    f.controller.close()
    f.center.post(name: .mcoIosExecutionAudioDiagnosticsChanged, object: nil)
    XCTAssertEqual(messenger.events.filter { $0.1.method == "diagnostics" }.count, 1)
  }

  func testNativeAudioDiagnosticsSnapshotDoesNotArmOrStartPlayer() {
    let check = {
      let backend = ImmortalizerExecutionBackend()
      let armed = backend.isArmed
      let running = backend.audioRunning
      let snapshot = backend.audioDiagnostics
      XCTAssertEqual(backend.isArmed, armed)
      XCTAssertEqual(backend.audioRunning, running)
      XCTAssertNotNil(snapshot["ioBufferDuration"])
      XCTAssertNotNil(snapshot["preferredIOBufferDuration"])
      XCTAssertNil(snapshot["deviceName"])
      XCTAssertNil(snapshot["uid"])
    }
    if Thread.isMainThread { check() } else { DispatchQueue.main.sync(execute: check) }
  }

  func testExecutionPowerOptionsParseStrictlyAndKeepManualOff() throws {
    let f = executionFixture(background: true)
    let messenger = PresentationTestMessenger()
    let channel = "mco_advanced/ios_execution"
    f.controller.register(binaryMessenger: messenger, viewController: { nil })
    f.controller.configure(eligible: true)
    f.controller.setManualAllowed(false)
    let options = IosImmortalizerPowerOptions(pauseUiFrames: true, leanHooks: true,
      withoutAudio: true, useOutputSampleRate: true, audioBufferMilliseconds: 200, loopSeconds: 10)
    XCTAssertEqual(IosImmortalizerPowerOptions.parse(options.arguments), options)
    _ = try messenger.call(channel, method: "configurePower", arguments: options.arguments)
    XCTAssertEqual(f.controller.powerOptions, options)
    XCTAssertEqual(f.backend.powerRequests, [options])
    XCTAssertTrue(f.controller.eligible)
    XCTAssertFalse(f.controller.manualAllowed)
    XCTAssertFalse(f.controller.armed)
    XCTAssertFalse(f.backend.audioRunning)
    let snapshot = try XCTUnwrap(try messenger.call(channel, method: "diagnostics") as? [String: Any])
    XCTAssertEqual((snapshot["powerOptions"] as? [String: Any])?["audioBufferMilliseconds"] as? Int, 200)
    for (key, value) in [("schema", 2 as Any), ("schema", true as Any),
                         ("pauseUiFrames", 1 as Any), ("loopSeconds", 11 as Any),
                         ("audioBufferMilliseconds", 15 as Any),
                         ("audioBufferMilliseconds", Double.nan as Any)] {
      var invalid = options.arguments
      invalid[key] = value
      XCTAssertNil(IosImmortalizerPowerOptions.parse(invalid))
      let reply = try messenger.call(channel, method: "configurePower", arguments: invalid)
      XCTAssertEqual((reply as? FlutterError)?.code, "bad_args")
    }
    XCTAssertEqual(f.backend.powerRequests.count, 1)
    XCTAssertFalse(f.controller.manualAllowed)
    f.controller.close()
    XCTAssertEqual(f.backend.powerRequests.last, IosImmortalizerPowerOptions())
    XCTAssertFalse(f.preferences.bool(forKey: IosBackgroundExecutionController.manualAllowedKey))
  }

  func testExecutionWithoutAudioKeepsCompatibilityAndRestoresOnlyEligibleBackground() {
    let f = executionFixture(background: true)
    f.controller.configure(eligible: true)
    XCTAssertTrue(f.backend.audioRunning)
    let noAudio = IosImmortalizerPowerOptions(withoutAudio: true,
      audioBufferMilliseconds: 100, loopSeconds: 5)
    XCTAssertTrue(f.controller.configurePower(noAudio))
    XCTAssertTrue(f.controller.armed)
    XCTAssertTrue(f.controller.compatibilityRequired)
    XCTAssertFalse(f.backend.audioRunning)
    XCTAssertEqual(f.backend.audioStops, 1)
    // Repeated requests do not restart the audio path.
    XCTAssertTrue(f.controller.configurePower(noAudio))
    XCTAssertEqual(f.backend.powerRequests.count, 1)
    var audio = noAudio
    audio.withoutAudio = false
    XCTAssertTrue(f.controller.configurePower(audio))
    XCTAssertTrue(f.backend.audioRunning)
    XCTAssertEqual(f.backend.audioStarts, 2)
    f.center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    XCTAssertFalse(f.backend.audioRunning)
    audio.loopSeconds = 10
    XCTAssertTrue(f.controller.configurePower(audio))
    XCTAssertFalse(f.backend.audioRunning)
    f.controller.configure(eligible: false)
    f.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
    XCTAssertTrue(f.controller.configurePower(IosImmortalizerPowerOptions()))
    XCTAssertFalse(f.backend.audioRunning)
  }

  func testExecutionRejectedPowerRequestRollsBackWithoutStartingOrChangingEligibility() {
    let f = executionFixture()
    f.backend.canConfigure = false
    XCTAssertFalse(f.controller.configurePower(IosImmortalizerPowerOptions(withoutAudio: true)))
    XCTAssertEqual(f.controller.powerOptions, IosImmortalizerPowerOptions())
    XCTAssertTrue(f.backend.armRequests.isEmpty)
    XCTAssertFalse(f.controller.eligible)
    XCTAssertTrue(f.controller.manualAllowed)
    XCTAssertEqual(f.backend.audioStarts, 0)
  }

  func testSilentWavHeaderAndBoundsWithoutStartingAudio() throws {
    func u32(_ data: Data, _ offset: Int) -> UInt32 {
      (0..<4).reduce(UInt32(0)) { $0 | (UInt32(data[offset + $1]) << ($1 * 8)) }
    }
    let original = try XCTUnwrap(ImmortalizerExecutionBackend.silentWav(sampleRate: 8000, seconds: 1))
    let header: [UInt8] = [
      82,73,70,70,164,62,0,0,87,65,86,69,102,109,116,32,16,0,0,0,1,0,1,0,
      64,31,0,0,128,62,0,0,2,0,16,0,100,97,116,97,128,62,0,0
    ]
    XCTAssertEqual(Array(original.prefix(44)), header)
    XCTAssertEqual(original.count, 16044)
    for (rate, seconds) in [(8000, 10), (44100, 3), (48000, 10), (192000, 10)] {
      let data = try XCTUnwrap(ImmortalizerExecutionBackend.silentWav(sampleRate: rate, seconds: seconds))
      XCTAssertEqual(data.count, 44 + rate * seconds * 2)
      XCTAssertEqual(u32(data, 4), UInt32(data.count - 8))
      XCTAssertEqual(u32(data, 24), UInt32(rate))
      XCTAssertEqual(u32(data, 28), UInt32(rate * 2))
      XCTAssertEqual(u32(data, 40), UInt32(data.count - 44))
      XCTAssertTrue(data.dropFirst(44).allSatisfy { $0 == 0 })
    }
    for (rate, seconds) in [(-1, 1), (7999, 1), (192001, 1), (8000, 0), (8000, 11)] {
      XCTAssertNil(ImmortalizerExecutionBackend.silentWav(sampleRate: rate, seconds: seconds))
    }
  }

  func testLeanClassifierKeepsLegacyTokenSemanticsWithoutArmingBackend() {
    let check = {
      let backend = ImmortalizerExecutionBackend()
      // The test host has no authorized TCP session; do not install private hooks.
      guard !backend.isArmed else {
        XCTFail("Classifier test requires an unarmed test host")
        return
      }
      defer { _ = backend.configurePower(IosImmortalizerPowerOptions()) }
      let corpus = ["", "foreground = NotSet", "foreground = No", "foreground = NO;",
        "foreground = BSSettingFlagNo }", "foreground = YES", "foreground = NoOther",
        "FBSceneSnapshotAction:", "hostContextIdentifierForSnapshotting = 0"]
      var legacy: [Bool] = []
      for lean in [false, true] {
        XCTAssertTrue(backend.configurePower(IosImmortalizerPowerOptions(leanHooks: lean)))
        var results: [Bool] = []
        for description in corpus {
          for background in [false, true] {
            for transitioning in [false, true] {
              results.append(ImmortalizerExecutionBackend.defersDiff(description,
                background: background, transitioning: transitioning))
            }
          }
        }
        if lean { XCTAssertEqual(results, legacy) } else { legacy = results }
      }
      XCTAssertFalse(backend.isArmed)
      XCTAssertFalse(backend.audioRunning)
    }
    if Thread.isMainThread { check() } else { DispatchQueue.main.sync(execute: check) }
  }

  func testImmortalizerDiffClassifierWithoutInstallingPrivateHooks() {
    for marker in ["foreground = NotSet", "foreground = No", "foreground = BSSettingFlagNo",
                   "foreground = NO", "hostContextIdentifierForSnapshotting = 0",
                   "scenePresenterRenderIdentifierForSnapshotting = 0",
                   "targetOfEventDeferringEnvironments = (empty)", "FBSceneSnapshotAction:"] {
      XCTAssertTrue(ImmortalizerExecutionBackend.suppressesDiff("diff { \(marker) }"))
    }
    for marker in ["foreground = YES", "foreground = BSSettingFlagYes", "other setting", ""] {
      XCTAssertFalse(ImmortalizerExecutionBackend.suppressesDiff(marker))
    }
    for marker in ["foreground = NotSet", "FBSceneSnapshotAction:", "hostContextIdentifierForSnapshotting = 0"] {
      XCTAssertFalse(ImmortalizerExecutionBackend.defersDiff(marker, background: false, transitioning: false))
      XCTAssertTrue(ImmortalizerExecutionBackend.defersDiff(marker, background: true, transitioning: false))
      XCTAssertTrue(ImmortalizerExecutionBackend.defersDiff(marker, background: false, transitioning: true))
    }
    for marker in ["foreground = No", "foreground = NO;", "foreground = BSSettingFlagNo }"] {
      XCTAssertTrue(ImmortalizerExecutionBackend.defersDiff(marker, background: false, transitioning: false))
    }
  }
}

final class ExecutionButtonTests: XCTestCase {
  private func fixture() -> (IosBackgroundExecutionButton, ButtonDockClock) {
    let clock = ButtonDockClock()
    let button = IosBackgroundExecutionButton(schedule: clock.schedule,
      animate: { _, changes, completion in changes(); completion() })
    button.install(in: UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)))
    addTeardownBlock { button.close() }
    return (button, clock)
  }

  func testOriginalButtonAndHandleGeometryAndFiveSecondDock() throws {
    let (view, clock) = fixture()
    let button = try XCTUnwrap(view.button)
    let handle = try XCTUnwrap(view.handle)
    XCTAssertEqual(button.bounds.size, CGSize(width: 50, height: 50))
    XCTAssertEqual(button.center, CGPoint(x: 365, y: 225))
    XCTAssertEqual(button.layer.cornerRadius, 25)
    XCTAssertEqual(button.tintColor, UIColor.systemBlue)
    XCTAssertEqual(button.backgroundColor, UIColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1))
    XCTAssertEqual(handle.bounds.size, CGSize(width: 15, height: 50))
    XCTAssertEqual(handle.subviews.first?.frame, CGRect(x: 6.5, y: 10, width: 3, height: 30))
    XCTAssertTrue(clock.delays.isEmpty) // No timer before display.
    view.show()
    view.show()
    XCTAssertEqual(clock.delays, [5]) // State notifications do not postpone docking.
    clock.fire()
    XCTAssertTrue(view.docked)
    XCTAssertTrue(button.isHidden)
    XCTAssertEqual(button.transform, CGAffineTransform(scaleX: 0.5, y: 0.5))
    XCTAssertEqual(button.alpha, 0)
    XCTAssertFalse(handle.isHidden)
    XCTAssertEqual(handle.alpha, 1)
    XCTAssertEqual(handle.frame, CGRect(x: 375, y: 200, width: 15, height: 50))
    XCTAssertNil(clock.pending) // One-shot; nothing periodic remains.
    view.undock()
    XCTAssertFalse(view.docked)
    XCTAssertFalse(button.isHidden)
    XCTAssertTrue(handle.isHidden)
    XCTAssertEqual(button.alpha, 1)
    XCTAssertEqual(button.transform, .identity)
    XCTAssertEqual(button.center, CGPoint(x: 362.5, y: 225))
    XCTAssertEqual(clock.delays, [5, 5])
  }

  func testBothEdgesAndVerticalLimitsMatchOriginal() throws {
    let (view, clock) = fixture()
    let button = try XCTUnwrap(view.button)
    button.center = CGPoint(x: 100, y: -50)
    view.snapToEdge()
    XCTAssertEqual(button.center, CGPoint(x: 25, y: 25))
    view.show()
    clock.fire()
    XCTAssertEqual(view.handle?.frame, CGRect(x: 0, y: 0, width: 15, height: 50))
    view.undock()
    XCTAssertEqual(button.center, CGPoint(x: 27.5, y: 25))
    button.center = CGPoint(x: 380, y: 1000)
    view.snapToEdge()
    XCTAssertEqual(button.center, CGPoint(x: 365, y: 819))
  }

  func testHideCancelsIdleWorkAndPreservesDockAndPositionAcrossBackground() throws {
    let (view, clock) = fixture()
    view.show()
    let stale = try XCTUnwrap(clock.pending)
    view.hide()
    XCTAssertNil(clock.pending)
    stale()
    XCTAssertFalse(view.docked)
    view.show()
    clock.fire()
    let position = view.handle?.frame
    view.hide()
    view.show()
    XCTAssertTrue(view.docked)
    XCTAssertEqual(view.handle?.frame, position)
    XCTAssertNil(clock.pending)
    XCTAssertFalse(try XCTUnwrap(view.handle).isHidden)
    view.close()
    XCTAssertNil(view.window)
  }

  func testManualOffUsesOriginalRedAndDoesNotChangeExecutionOnDock() throws {
    let (view, clock) = fixture()
    var toggles = 0
    view.onToggle = { toggles += 1 }
    view.update(host: nil, visible: false, selected: false)
    view.install(in: UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)))
    XCTAssertEqual(view.button?.tintColor, UIColor.systemRed)
    view.show()
    clock.fire()
    view.undock()
    XCTAssertEqual(toggles, 0)
  }

  func testLateDockCompletionCannotRevealHandleAfterHide() throws {
    var completions: [() -> Void] = []
    let clock = ButtonDockClock()
    let view = IosBackgroundExecutionButton(schedule: clock.schedule,
      animate: { _, changes, completion in changes(); completions.append(completion) })
    defer { view.close() }
    view.install(in: UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)))
    view.show()
    clock.fire()
    view.hide()
    let count = completions.count
    for completion in completions { completion() }
    XCTAssertEqual(completions.count, count) // No second animation/timer after hiding.
    XCTAssertTrue(try XCTUnwrap(view.window).isHidden)
    XCTAssertNil(clock.pending)
  }
}

private final class ButtonDockClock {
  var pending: (() -> Void)?
  var delays: [TimeInterval] = []
  func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) -> (() -> Void) {
    delays.append(delay)
    pending = work
    return { [weak self] in self?.pending = nil }
  }
  func fire() {
    let work = pending
    pending = nil
    work?()
  }
}

private final class ExecutionTestBackend: IosBackgroundExecutionBackend {
  var canArm = true
  var canConfigure = true
  private(set) var powerRequests: [IosImmortalizerPowerOptions] = []
  private var powerOptions = IosImmortalizerPowerOptions()
  var onArm: ((Bool) -> Void)?
  private var armed = false
  private var background = false
  private(set) var armRequests: [Bool] = []
  private(set) var audioRunning = false
  private(set) var audioStarts = 0
  private(set) var audioStops = 0
  var audioDiagnostics: [String: Any] {
    return ["schema": 1, "running": audioRunning, "sampleRate": 48000.0,
            "backendArmed": armed, "physicalBackground": background,
            "ioBufferDuration": 0.02, "preferredIOBufferDuration": 0.005]
  }

  func setArmed(_ armed: Bool) -> Bool {
    armRequests.append(armed)
    self.armed = armed && canArm
    onArm?(self.armed)
    updateAudio()
    return self.armed
  }

  func setBackground(_ background: Bool) {
    self.background = background
    updateAudio()
  }

  func configurePower(_ options: IosImmortalizerPowerOptions) -> Bool {
    guard canConfigure else { return false }
    powerRequests.append(options)
    powerOptions = options
    updateAudio()
    return true
  }

  private func updateAudio() {
    let running = armed && background && !powerOptions.withoutAudio
    if running != audioRunning {
      if running { audioStarts += 1 } else { audioStops += 1 }
      audioRunning = running
    }
  }
}

private final class GpuTestTarget: IosPresentationGpuTarget {
  private(set) var writes: [Bool] = []
  var isGpuDisabled: Bool {
    didSet { writes.append(isGpuDisabled) }
  }

  init(disabled: Bool = false) { isGpuDisabled = disabled }
}

private final class GpuRecheckQueue {
  private(set) var pending: [() -> Void] = []

  func schedule(_ work: @escaping () -> Void) { pending.append(work) }

  func drain() {
    let work = pending
    pending.removeAll()
    for callback in work { callback() }
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

  func call(_ channel: String, method: String, arguments: Any? = nil) throws -> Any? {
    let handler = try XCTUnwrap(handlers[channel])
    var reply: Data?
    var completed = false
    handler(codec.encodeMethodCall(FlutterMethodCall(methodName: method, arguments: arguments))) {
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
