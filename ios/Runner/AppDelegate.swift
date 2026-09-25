import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications so notification taps are
    // forwarded to Dart, including taps that launch the app from a cold start.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "IosBleProxyAdapter") {
      IosBleProxyAdapter.register(with: registrar)
    }
    if let registrar = self.registrar(forPlugin: "IosBleCentralAdapter") {
      IosBleCentralAdapter.register(with: registrar)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
