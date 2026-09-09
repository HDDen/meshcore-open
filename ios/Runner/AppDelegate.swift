import Flutter
import NetworkExtension
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let backgroundTcpManagerName = "MCO Advanced Background TCP"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Required by flutter_local_notifications so notification taps are
    // forwarded to Dart, including taps that launch the app from a cold start.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "mco_advanced/ios_wifi_ssid",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "currentSsid" else {
          result(FlutterMethodNotImplemented)
          return
        }
        NEHotspotNetwork.fetchCurrent { network in
          DispatchQueue.main.async {
            result(network?.ssid)
          }
        }
      }

      let backgroundTcpChannel = FlutterMethodChannel(
        name: "mco_advanced/ios_background_tcp",
        binaryMessenger: controller.binaryMessenger
      )
      backgroundTcpChannel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "configure" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.configureBackgroundTcp(call: call, result: result)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configureBackgroundTcp(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let host = args["host"] as? String,
          let port = args["port"] as? Int,
          let wifiSsid = args["wifiSsid"] as? String,
          let enabled = args["enabled"] as? Bool else {
      result(FlutterError(code: "bad_args", message: "Invalid background TCP arguments", details: nil))
      return
    }

    guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          port > 0,
          port <= 65535 else {
      result(FlutterError(code: "bad_endpoint", message: "Invalid TCP endpoint", details: nil))
      return
    }

    if enabled && wifiSsid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      result(FlutterError(code: "bad_ssid", message: "Wi-Fi SSID is required", details: nil))
      return
    }

    NEAppPushManager.loadAllFromPreferences { [weak self] managers, error in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "load_failed", message: error.localizedDescription, details: nil))
        }
        return
      }

      guard let self = self else {
        DispatchQueue.main.async {
          result(FlutterError(code: "app_unavailable", message: "Application delegate is unavailable", details: nil))
        }
        return
      }
      let providerBundleIdentifier = "\(Bundle.main.bundleIdentifier ?? "com.monitormx.mcoadvanced").MeshCoreBackgroundTcpExtension"
      let manager = managers?.first(where: { existing in
        existing.localizedDescription == self.backgroundTcpManagerName ||
        existing.providerBundleIdentifier == providerBundleIdentifier
      }) ?? NEAppPushManager()

      manager.localizedDescription = self.backgroundTcpManagerName
      manager.providerBundleIdentifier = providerBundleIdentifier
      manager.matchSSIDs = enabled ? [wifiSsid.trimmingCharacters(in: .whitespacesAndNewlines)] : []
      manager.providerConfiguration = [
        "host": host.trimmingCharacters(in: .whitespacesAndNewlines),
        "port": port,
        "appName": "MeshCoreOpen;cap=mctxt,mcmp,aeic"
      ]
      manager.isEnabled = enabled
      manager.saveToPreferences { saveError in
        DispatchQueue.main.async {
          if let saveError = saveError {
            result(FlutterError(code: "save_failed", message: saveError.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      }
    }
  }
}
