import Flutter
import Foundation

protocol IosPresentationGpuTarget: AnyObject {
  var isGpuDisabled: Bool { get set }
}

extension FlutterEngine: IosPresentationGpuTarget {}

/// Ограничивает только GPU API engine; не отправляет Dart lifecycle-событий.
final class IosPresentationGpuGuard {
  private let targetProvider: () -> IosPresentationGpuTarget?
  private let scheduleRecheck: (@escaping () -> Void) -> Void
  private weak var target: IosPresentationGpuTarget?
  private var ownsRestriction = false
  private var active = true
  private var enabled = false
  private var generation = 0

  init(targetProvider: @escaping () -> IosPresentationGpuTarget?,
       scheduleRecheck: @escaping (@escaping () -> Void) -> Void = {
         DispatchQueue.main.async(execute: $0)
       }) {
    self.targetProvider = targetProvider
    self.scheduleRecheck = scheduleRecheck
  }

  var available: Bool { target != nil }
  var gpuDisabled: Bool? { target?.isGpuDisabled }

  func update(enabled: Bool, active: Bool) {
    generation &+= 1
    self.enabled = enabled
    self.active = active
    apply()
    guard enabled && !active else { return }
    let expectedGeneration = generation
    // Flutter может включить GPU своим обработчиком того же уведомления.
    // Один повтор после dispatch учитывает оба порядка; таймеров/опроса нет.
    scheduleRecheck { [weak self] in
      guard let self = self, self.generation == expectedGeneration else { return }
      self.apply()
    }
  }

  private func apply() {
    // Один guard принадлежит одному messenger/engine. Не переносим его
    // ограничение на другой ещё живой engine при смене viewController.
    if target == nil {
      target = targetProvider()
      ownsRestriction = false
    }
    guard let target = target else { return }
    if enabled && !active {
      if !target.isGpuDisabled {
        ownsRestriction = true
        target.isGpuDisabled = true
      }
    } else {
      releaseIfActive()
    }
  }

  private func releaseIfActive() {
    // Не включаем чужой GPU и не снимаем запрет при физически неактивной сцене.
    guard active && ownsRestriction else { return }
    if target?.isGpuDisabled == true {
      target?.isGpuDisabled = false
    }
    ownsRestriction = false
  }

  func close() {
    generation &+= 1
    enabled = false
    releaseIfActive()
  }

  deinit { releaseIfActive() }
}
