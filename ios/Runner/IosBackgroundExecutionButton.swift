import UIKit

private final class ExecutionButtonWindow: UIWindow {
  override var canBecomeKey: Bool { false }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === rootViewController?.view ? nil : hit
  }
}

/// An icon-only native toggle. Never takes Flutter's key window; no dock timer.
final class IosBackgroundExecutionButton: NSObject {
  var onToggle: (() -> Void)?
  private var window: ExecutionButtonWindow?
  private var button: UIButton?

  func update(host: UIViewController?, visible: Bool, selected: Bool) {
    guard visible, let scene = host?.viewIfLoaded?.window?.windowScene,
          scene.activationState == .foregroundActive else {
      hide()
      return
    }
    if window?.windowScene !== scene {
      hide()
      let window = ExecutionButtonWindow(windowScene: scene)
      window.frame = scene.coordinateSpace.bounds
      let root = UIViewController()
      root.view.backgroundColor = .clear
      window.rootViewController = root
      window.backgroundColor = .clear
      window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
      let button = UIButton(type: .system)
      button.frame = CGRect(x: max(0, window.bounds.width - 64), y: 120, width: 48, height: 48)
      button.layer.cornerRadius = 24
      button.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
      button.setImage(UIImage(systemName: "hourglass"), for: .normal)
      button.accessibilityLabel = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      button.addTarget(self, action: #selector(toggle), for: .touchUpInside)
      button.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
      root.view.addSubview(button)
      self.window = window
      self.button = button
      window.isHidden = false
    }
    button?.isSelected = selected
    button?.accessibilityTraits = selected ? [.button, .selected] : [.button]
    button?.tintColor = selected ? .systemBlue : .systemGray
  }

  @objc private func toggle() { onToggle?() }

  @objc private func drag(_ gesture: UIPanGestureRecognizer) {
    guard let button = button, let root = window?.rootViewController?.view else { return }
    let translation = gesture.translation(in: root)
    let bounds = root.bounds.inset(by: root.safeAreaInsets).insetBy(dx: 24, dy: 24)
    button.center = CGPoint(x: min(max(button.center.x + translation.x, bounds.minX), bounds.maxX),
                            y: min(max(button.center.y + translation.y, bounds.minY), bounds.maxY))
    gesture.setTranslation(.zero, in: root)
  }

  func hide() {
    window?.isHidden = true
    window = nil
    button = nil
  }
}
