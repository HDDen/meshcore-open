// SPDX-License-Identifier: GPL-3.0-or-later
// FloatingButtonWindow / CustomToastView: Copyright (C) 2025 Serge Alagon.
// Swift port for MCOa (2026); see ImmortalizerBackend/NOTICE.md and LICENSE.
import UIKit

private final class ExecutionButtonWindow: UIWindow {
  override var canBecomeKey: Bool { false }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === rootViewController?.view ? nil : hit
  }
}

/// Original visuals; execution policy and audio stay outside this view.
final class IosBackgroundExecutionButton: NSObject {
  typealias Schedule = (TimeInterval, @escaping () -> Void) -> (() -> Void)
  typealias Animate = (TimeInterval, @escaping () -> Void, @escaping () -> Void) -> Void
  var onToggle: (() -> Void)?
  private(set) var window: UIWindow?
  private(set) var button: UIButton?
  private(set) var handle: UIView?
  private(set) var docked = false
  private let schedule: Schedule
  private let animate: Animate
  private var cancelDock: (() -> Void)?
  private var toast: ExecutionToastView?
  private var selected = true
  private var visible = false
  private var revision = 0

  init(schedule: @escaping Schedule = { delay, work in
    let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in work() }
    return { timer.invalidate() }
  }, animate: @escaping Animate = { duration, changes, completion in
    UIView.animate(withDuration: duration, animations: changes) { _ in completion() }
  }) {
    self.schedule = schedule
    self.animate = animate
    super.init()
  }

  func update(host: UIViewController?, visible: Bool, selected: Bool) {
    self.selected = selected
    guard visible, let scene = host?.viewIfLoaded?.window?.windowScene,
          scene.activationState == .foregroundActive else { hide(); return }
    if window?.windowScene !== scene {
      let window = ExecutionButtonWindow(windowScene: scene)
      window.frame = scene.coordinateSpace.bounds
      install(in: window)
    }
    updateColor()
    show()
  }

  // Also constructs the real views in native tests without a live scene.
  func install(in window: UIWindow) {
    close()
    let root = UIViewController()
    root.view.backgroundColor = .clear
    window.rootViewController = root
    window.backgroundColor = .clear
    window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
    let button = UIButton(type: .custom)
    button.frame = CGRect(x: window.bounds.width - 80, y: 200, width: 50, height: 50)
    button.backgroundColor = UIColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1)
    button.layer.cornerRadius = 25
    button.layer.masksToBounds = true
    button.setImage(UIImage(systemName: "hourglass.tophalf.fill"), for: .normal)
    button.accessibilityLabel = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    button.addTarget(self, action: #selector(toggle), for: .touchUpInside)
    button.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
    root.view.addSubview(button)
    let handle = UIView(frame: CGRect(x: 0, y: 0, width: 15, height: 50))
    handle.backgroundColor = UIColor(white: 0.2, alpha: 0.7)
    handle.layer.cornerRadius = 6
    handle.layer.masksToBounds = true
    handle.alpha = 0
    handle.isHidden = true
    let line = UIView(frame: CGRect(x: 6.5, y: 10, width: 3, height: 30))
    line.backgroundColor = .white
    line.layer.cornerRadius = 1
    line.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin]
    handle.addSubview(line)
    handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHandle(_:))))
    handle.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(undock)))
    handle.isAccessibilityElement = true
    handle.accessibilityLabel = button.accessibilityLabel
    handle.accessibilityTraits = .button
    root.view.addSubview(handle)
    self.window = window
    self.button = button
    self.handle = handle
    window.isHidden = true
    updateColor()
    snapToEdge()
  }

  func show() {
    guard let window = window, !visible else { return }
    visible = true
    // Keep Flutter's key window; no makeKeyAndVisible / deferred key restoration.
    window.isHidden = false
    if !docked { startDockTimer() }
  }

  private func updateColor() {
    button?.isSelected = selected
    button?.accessibilityTraits = selected ? [.button, .selected] : [.button]
    button?.tintColor = selected ? .systemBlue : .systemRed
  }

  private func startDockTimer() {
    cancelDock?()
    cancelDock = nil
    guard visible, !docked else { return }
    let revision = self.revision
    cancelDock = schedule(5) { [weak self] in
      guard let self = self, self.visible, self.revision == revision else { return }
      self.cancelDock = nil
      self.dock()
    }
  }

  func snapToEdge() {
    guard let button = button, let window = window else { return }
    let half = button.frame.width / 2
    let halfHeight = button.frame.height / 2
    let center = CGPoint(x: button.center.x < window.bounds.width / 2 ? half : window.bounds.width - half,
                         y: max(halfHeight, min(window.bounds.height - halfHeight, button.center.y)))
    animate(0.3, { button.center = center }, {})
  }

  func dock() {
    guard visible, !docked, let button = button, let handle = handle, let window = window else { return }
    cancelDock?()
    cancelDock = nil
    docked = true
    let revision = self.revision
    handle.frame.origin = CGPoint(x: button.center.x < window.bounds.width / 2 ? 0 : window.bounds.width - 15,
                                  y: button.frame.origin.y + (button.frame.height - 50) / 2)
    animate(0.3, {
      button.alpha = 0
      button.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
    }, { [weak self] in
      guard let self = self, self.visible, self.revision == revision, self.docked else { return }
      button.isHidden = true
      handle.isHidden = false
      self.animate(0.2, { handle.alpha = 1 }, {})
    })
  }

  @objc func undock() {
    guard visible, docked, let button = button, let handle = handle, let window = window else { return }
    docked = false
    button.isHidden = false
    let revision = self.revision
    // Original reads the still-scaled frame, before restoring identity.
    let inset = handle.frame.width + button.frame.width / 2
    button.center = CGPoint(x: handle.frame.minX < window.bounds.width / 2 ? inset : window.bounds.width - inset,
                            y: handle.center.y)
    animate(0.3, {
      handle.alpha = 0
      button.alpha = 1
      button.transform = .identity
    }, { [weak self] in
      guard let self = self, self.visible, self.revision == revision, !self.docked else { return }
      handle.isHidden = true
      self.startDockTimer()
    })
  }

  @objc private func toggle() {
    guard visible, !docked, let button = button else { return }
    let revision = self.revision
    animate(0.1, {
      button.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
      let feedback = UIImpactFeedbackGenerator(style: .heavy)
      feedback.prepare()
      feedback.impactOccurred()
    }, { [weak self] in
      guard let self = self, self.visible, self.revision == revision, !self.docked else { return }
      self.animate(0.1, { button.transform = .identity }, {})
      self.onToggle?()
      // The controller synchronously supplies the new persistent manual state.
      if let root = self.window?.rootViewController?.view {
        self.toast?.removeFromSuperview()
        let toast = ExecutionToastView(selected: self.selected)
        self.toast = toast
        toast.present(in: root)
      }
    })
  }

  @objc private func drag(_ gesture: UIPanGestureRecognizer) {
    guard visible, let button = button, let window = window else { return }
    if !docked { startDockTimer() }
    let delta = gesture.translation(in: window)
    animate(0.2, {
      button.center = CGPoint(x: button.center.x + delta.x, y: button.center.y + delta.y)
      gesture.setTranslation(.zero, in: window)
    }, {})
    if gesture.state == .ended { snapToEdge(); startDockTimer() }
  }

  @objc private func dragHandle(_ gesture: UIPanGestureRecognizer) {
    guard visible, let button = button, let handle = handle, let window = window else { return }
    if gesture.state == .began { undock(); return }
    let delta = gesture.translation(in: window)
    button.center = CGPoint(x: handle.center.x + delta.x, y: handle.center.y + delta.y)
    gesture.setTranslation(.zero, in: window)
    if gesture.state == .ended { snapToEdge(); startDockTimer() }
  }

  func hide() {
    visible = false
    revision += 1
    cancelDock?()
    cancelDock = nil
    toast?.removeFromSuperview()
    toast = nil
    window?.isHidden = true
    button?.layer.removeAllAnimations()
    handle?.layer.removeAllAnimations()
    // Preserve position/state across background, even if an animation was interrupted.
    button?.isHidden = docked
    button?.alpha = docked ? 0 : 1
    button?.transform = docked ? CGAffineTransform(scaleX: 0.5, y: 0.5) : .identity
    handle?.isHidden = !docked
    handle?.alpha = docked ? 1 : 0
  }

  func close() {
    hide()
    window = nil
    button = nil
    handle = nil
    docked = false
  }

  deinit { close() }
}

private final class ExecutionToastView: UIView {
  private var hideWork: DispatchWorkItem?

  init(selected: Bool) {
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    let container = UIView()
    container.backgroundColor = UIColor(red: 0.125, green: 0.125, blue: 0.125, alpha: 1)
    container.layer.cornerRadius = 25
    container.layer.masksToBounds = true
    container.layer.shadowColor = UIColor.black.cgColor
    container.layer.shadowOpacity = 0.18
    container.layer.shadowOffset = CGSize(width: 0, height: 8)
    container.layer.shadowRadius = 10
    container.translatesAutoresizingMaskIntoConstraints = false
    addSubview(container)
    let horizontal = UIStackView()
    horizontal.axis = .horizontal
    horizontal.alignment = .center
    horizontal.spacing = 2
    horizontal.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
    horizontal.isLayoutMarginsRelativeArrangement = true
    horizontal.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(horizontal)
    let icon = UIImageView(image: UIImage(systemName: selected ? "hourglass.bottomhalf.fill" : "arrow.uturn.left.circle.fill"))
    icon.contentMode = .scaleAspectFit
    horizontal.addArrangedSubview(icon)
    let vertical = UIStackView()
    vertical.axis = .vertical
    vertical.alignment = .center
    vertical.spacing = 2
    vertical.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    vertical.isLayoutMarginsRelativeArrangement = true
    horizontal.addArrangedSubview(vertical)
    for (text, color) in [(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "", UIColor.white),
                          (selected ? "Immortalized" : "At Rest", UIColor.lightGray)] {
      let label = UILabel()
      label.text = text
      label.textColor = color
      label.font = .boldSystemFont(ofSize: 12)
      label.textAlignment = .center
      vertical.addArrangedSubview(label)
    }
    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      container.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
      horizontal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      horizontal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      horizontal.topAnchor.constraint(equalTo: container.topAnchor),
      horizontal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func present(in view: UIView) {
    translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(self)
    NSLayoutConstraint.activate([
      centerXAnchor.constraint(equalTo: view.centerXAnchor),
      topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
      widthAnchor.constraint(equalTo: view.widthAnchor, constant: -190),
      heightAnchor.constraint(equalToConstant: 70)
    ])
    view.layoutIfNeeded()
    transform = CGAffineTransform(translationX: 0, y: -bounds.height)
    UIView.animate(withDuration: 0.3) { self.transform = .identity }
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      UIView.animate(withDuration: 0.2, animations: {
        self.transform = CGAffineTransform(translationX: 0, y: -self.bounds.height - 30)
      }) { _ in self.removeFromSuperview() }
    }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
  }

  override func removeFromSuperview() {
    hideWork?.cancel()
    hideWork = nil
    super.removeFromSuperview()
  }
}
