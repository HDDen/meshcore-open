import CoreBluetooth
import Flutter
import Foundation
import UIKit

final class IosBleProxyAdapter: NSObject, CBPeripheralManagerDelegate, FlutterStreamHandler {
  private static let methodChannelName = "mco_service/ios_ble_proxy"
  private static let eventChannelName = "mco_service/ios_ble_proxy/events"
  private static let restoreIdentifier = "mco.advanced.ble_proxy.peripheral"
  private static var instance: IosBleProxyAdapter?

  static func register(with registrar: FlutterPluginRegistrar) {
    let adapter = IosBleProxyAdapter()
    instance = adapter
    let messenger = registrar.messenger()
    let method = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    method.setMethodCallHandler(adapter.handle)
    events.setStreamHandler(adapter)
  }

  private var eventSink: FlutterEventSink?
  private var peripheralManager: CBPeripheralManager?
  private var serviceUuid: CBUUID?
  private var rxUuid: CBUUID?
  private var txUuid: CBUUID?
  private var txCharacteristic: CBMutableCharacteristic?
  private var rxCharacteristic: CBMutableCharacteristic?
  private var advertiseName: String?
  private var maxClients: Int = 1
  private var minimumFramePayload: Int = 20
  private var maximumFramePayload: Int = 176
  private var notifyIntervalMs: Int = 0
  private var requireBonding = false
  private var txRead = false
  private var rxWriteWithoutResponse = false
  private var isStarted = false
  private var pendingStart: FlutterResult?
  private var centrals: [UUID: CBCentral] = [:]
  private var notifyQueues: [UUID: [FlutterStandardTypedData]] = [:]
  private var isNotifying: Set<UUID> = []
  private var subscribedCentrals: Set<UUID> = []
  private var refusedCentrals: Set<UUID> = []
  private var lastNotifyAt: [UUID: Date] = [:]

  private override init() {
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "start":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Missing BLE proxy arguments", details: nil))
        return
      }
      start(args: args, result: result)
    case "stop":
      stop()
      result(nil)
    case "refreshAdvertising":
      if let args = call.arguments as? [String: Any] {
        advertiseName = args["name"] as? String
      }
      refreshAdvertising()
      result(nil)
    case "send":
      guard
        let args = call.arguments as? [String: Any],
        let clientId = args["clientId"] as? String,
        let data = args["data"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "bad_args", message: "Missing notify payload", details: nil))
        return
      }
      send(clientId: clientId, data: data, result: result)
    case "closeClient":
      guard
        let args = call.arguments as? [String: Any],
        let clientId = args["clientId"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Missing client id", details: nil))
        return
      }
      closeClient(clientId)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func start(args: [String: Any], result: @escaping FlutterResult) {
    if isStarted {
      result(nil)
      return
    }
    guard
      let service = uuid(from: args["serviceUuid"]),
      let rx = uuid(from: args["rxUuid"]),
      let tx = uuid(from: args["txUuid"])
    else {
      result(FlutterError(code: "bad_uuid", message: "Invalid BLE proxy UUID", details: nil))
      return
    }

    serviceUuid = service
    rxUuid = rx
    txUuid = tx
    advertiseName = args["name"] as? String
    maxClients = max(1, args["maxClients"] as? Int ?? 1)
    minimumFramePayload = max(20, args["minimumFramePayload"] as? Int ?? 20)
    maximumFramePayload = max(minimumFramePayload, args["maximumFramePayload"] as? Int ?? 176)
    notifyIntervalMs = max(0, args["notifyIntervalMs"] as? Int ?? 0)
    requireBonding = args["requireBonding"] as? Bool ?? false
    txRead = args["txRead"] as? Bool ?? false
    rxWriteWithoutResponse = args["rxWriteWithoutResponse"] as? Bool ?? false
    pendingStart = result

    peripheralManager = CBPeripheralManager(
      delegate: self,
      queue: DispatchQueue.main,
      options: [CBPeripheralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
    )
  }

  private func stop() {
    isStarted = false
    pendingStart = nil
    peripheralManager?.stopAdvertising()
    peripheralManager?.removeAllServices()
    peripheralManager = nil
    txCharacteristic = nil
    rxCharacteristic = nil
    centrals.removeAll()
    notifyQueues.removeAll()
    isNotifying.removeAll()
    subscribedCentrals.removeAll()
    refusedCentrals.removeAll()
    lastNotifyAt.removeAll()
  }

  private func configureGattIfNeeded() {
    guard
      !isStarted,
      let manager = peripheralManager,
      manager.state == .poweredOn,
      let serviceUuid,
      let rxUuid,
      let txUuid
    else { return }

    let readPermissions: CBAttributePermissions = txRead
      ? (requireBonding ? [.readEncryptionRequired] : [.readable])
      : []
    let writePermissions: CBAttributePermissions = requireBonding ? [.writeEncryptionRequired] : [.writeable]
    var txProperties: CBCharacteristicProperties = [.notify]
    if txRead {
      txProperties.insert(.read)
    }
    var rxProperties: CBCharacteristicProperties = [.write]
    if rxWriteWithoutResponse {
      rxProperties.insert(.writeWithoutResponse)
    }
    let tx = CBMutableCharacteristic(
      type: txUuid,
      properties: txProperties,
      value: nil,
      permissions: readPermissions
    )
    let rx = CBMutableCharacteristic(
      type: rxUuid,
      properties: rxProperties,
      value: nil,
      permissions: writePermissions
    )
    let service = CBMutableService(type: serviceUuid, primary: true)
    service.characteristics = [tx, rx]
    txCharacteristic = tx
    rxCharacteristic = rx
    manager.removeAllServices()
    manager.add(service)
  }

  private func refreshAdvertising() {
    guard isStarted, let manager = peripheralManager, manager.state == .poweredOn else { return }
    manager.stopAdvertising()
    startAdvertising()
  }

  private func startAdvertising() {
    guard let manager = peripheralManager, let serviceUuid else { return }
    var advertisement: [String: Any] = [CBAdvertisementDataServiceUUIDsKey: [serviceUuid]]
    if let advertiseName, !advertiseName.isEmpty {
      advertisement[CBAdvertisementDataLocalNameKey] = advertiseName
    }
    manager.startAdvertising(advertisement)
  }

  private func send(clientId: String, data: FlutterStandardTypedData, result: @escaping FlutterResult) {
    guard let uuid = UUID(uuidString: clientId), subscribedCentrals.contains(uuid) else {
      result(FlutterError(code: "unknown_client", message: "BLE client is not subscribed", details: nil))
      return
    }
    guard data.data.count <= maximumFramePayload else {
      result(FlutterError(code: "frame_too_large", message: "BLE frame exceeds link limit", details: maximumFramePayload))
      return
    }
    notifyQueues[uuid, default: []].append(data)
    drainNotifyQueue(for: uuid)
    result(nil)
  }

  private func drainNotifyQueue(for uuid: UUID) {
    guard !isNotifying.contains(uuid),
          let manager = peripheralManager,
          let characteristic = txCharacteristic,
          let central = centrals[uuid],
          subscribedCentrals.contains(uuid),
          var queue = notifyQueues[uuid],
          !queue.isEmpty
    else { return }

    let now = Date()
    if notifyIntervalMs > 0, let last = lastNotifyAt[uuid] {
      let elapsed = now.timeIntervalSince(last) * 1000
      if elapsed < Double(notifyIntervalMs) {
        isNotifying.insert(uuid)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(notifyIntervalMs - Int(elapsed))) { [weak self] in
          self?.isNotifying.remove(uuid)
          self?.drainNotifyQueue(for: uuid)
        }
        return
      }
    }

    let packet = queue.removeFirst()
    notifyQueues[uuid] = queue
    let accepted = manager.updateValue(packet.data, for: characteristic, onSubscribedCentrals: [central])
    if accepted {
      lastNotifyAt[uuid] = Date()
      if !queue.isEmpty {
        DispatchQueue.main.async { [weak self] in self?.drainNotifyQueue(for: uuid) }
      }
    } else {
      notifyQueues[uuid, default: []].insert(packet, at: 0)
      isNotifying.insert(uuid)
    }
  }

  private func closeClient(_ clientId: String) {
    guard let uuid = UUID(uuidString: clientId) else { return }
    centrals.removeValue(forKey: uuid)
    notifyQueues.removeValue(forKey: uuid)
    subscribedCentrals.remove(uuid)
    refusedCentrals.remove(uuid)
    isNotifying.remove(uuid)
    lastNotifyAt.removeValue(forKey: uuid)
    emit(["event": "closed", "clientId": clientId])
  }

  private func emit(_ event: [String: Any]) {
    eventSink?(event)
    if event["event"] as? String == "write" || event["event"] as? String == "subscribed" {
      DispatchQueue.main.async { [weak self] in
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "mco-ble-proxy-wake") {
          if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
          }
          task = .invalid
        }
        self?.emit(["event": "wake"])
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
          if task != .invalid {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
          }
        }
      }
    }
  }

  private func uuid(from value: Any?) -> CBUUID? {
    if let text = value as? String {
      return CBUUID(string: text)
    }
    if let bytes = value as? FlutterStandardTypedData, bytes.data.count == 16 {
      return CBUUID(data: bytes.data)
    }
    if let bytes = value as? [UInt8], bytes.count == 16 {
      return CBUUID(data: Data(bytes))
    }
    return nil
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    switch peripheral.state {
    case .poweredOn:
      configureGattIfNeeded()
    case .unsupported:
      pendingStart?(FlutterError(code: "unsupported", message: "Bluetooth LE advertising is not supported on this device", details: nil))
      pendingStart = nil
    case .unauthorized:
      pendingStart?(FlutterError(code: "unauthorized", message: "Bluetooth permission was not granted", details: nil))
      pendingStart = nil
    default:
      break
    }
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    if let error {
      pendingStart?(FlutterError(code: "add_service_failed", message: error.localizedDescription, details: nil))
      pendingStart = nil
      return
    }
    isStarted = true
    startAdvertising()
    pendingStart?(nil)
    pendingStart = nil
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
    guard characteristic.uuid == txUuid else { return }
    let uuid = central.identifier
    let notifyLength = min(maximumFramePayload, central.maximumUpdateValueLength)
    if notifyLength < minimumFramePayload {
      refusedCentrals.insert(uuid)
      emit(["event": "refused", "clientId": uuid.uuidString, "reason": "frameLimit"])
      return
    }
    if !subscribedCentrals.contains(uuid) && subscribedCentrals.count >= maxClients {
      refusedCentrals.insert(uuid)
      emit(["event": "refused", "clientId": uuid.uuidString, "reason": "clientLimit"])
      return
    }
    centrals[uuid] = central
    subscribedCentrals.insert(uuid)
    emit([
      "event": "subscribed",
      "clientId": uuid.uuidString,
      "address": "ble:\(uuid.uuidString)",
      "maximumNotifyLength": notifyLength,
    ])
    drainNotifyQueue(for: uuid)
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
    guard characteristic.uuid == txUuid else { return }
    closeClient(central.identifier.uuidString)
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
    guard request.characteristic.uuid == txUuid else {
      peripheral.respond(to: request, withResult: .requestNotSupported)
      return
    }
    request.value = Data()
    peripheral.respond(to: request, withResult: .success)
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    for request in requests {
      guard request.characteristic.uuid == rxUuid else {
        peripheral.respond(to: request, withResult: .requestNotSupported)
        continue
      }
      let uuid = request.central.identifier
      if refusedCentrals.contains(uuid) {
        peripheral.respond(to: request, withResult: .insufficientResources)
        continue
      }
      centrals[uuid] = request.central
      let value = request.value ?? Data()
      if value.count > 0 {
        emit([
          "event": "write",
          "clientId": uuid.uuidString,
          "address": "ble:\(uuid.uuidString)",
          "data": FlutterStandardTypedData(bytes: value),
        ])
      }
      peripheral.respond(to: request, withResult: .success)
    }
  }

  func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
    let uuids = Array(isNotifying)
    isNotifying.removeAll()
    for uuid in uuids {
      drainNotifyQueue(for: uuid)
    }
  }
}
