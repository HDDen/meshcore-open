import CoreBluetooth
import Flutter
import Foundation

final class IosBleCentralAdapter: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, FlutterStreamHandler {
  private static let methodChannelName = "mco_service/ios_ble_central"
  private static let eventChannelName = "mco_service/ios_ble_central/events"
  private static let restoreIdentifier = "mco.advanced.ble_central"
  private static var instance: IosBleCentralAdapter?

  static func register(with registrar: FlutterPluginRegistrar) {
    let adapter = IosBleCentralAdapter()
    instance = adapter
    let messenger = registrar.messenger()
    let method = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    let events = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    method.setMethodCallHandler(adapter.handle)
    events.setStreamHandler(adapter)
  }

  private var eventSink: FlutterEventSink?
  private var centralManager: CBCentralManager?
  private var targetPeripheral: CBPeripheral?
  private var serviceUuid: CBUUID?
  private var rxUuid: CBUUID?
  private var txUuid: CBUUID?
  private var rxCharacteristic: CBCharacteristic?
  private var txCharacteristic: CBCharacteristic?
  private var targetRemoteId: UUID?
  private var pendingConnect: FlutterResult?
  private var pendingSend: [FlutterResult] = []
  private var bufferedEvents: [[String: Any]] = []
  private var restoreEnabled = true
  private var reconnectOnRestore = false
  private let maxBufferedEvents = 200

  private override init() {
    super.init()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(true)
    case "connect":
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "bad_args", message: "Missing BLE central arguments", details: nil))
        return
      }
      connect(args: args, result: result)
    case "disconnect":
      disconnect()
      result(nil)
    case "send":
      guard
        let args = call.arguments as? [String: Any],
        let data = args["data"] as? FlutterStandardTypedData
      else {
        result(FlutterError(code: "bad_args", message: "Missing write payload", details: nil))
        return
      }
      send(data: data.data, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    flushBufferedEvents()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func connect(args: [String: Any], result: @escaping FlutterResult) {
    guard
      let remoteIdText = args["remoteId"] as? String,
      let remoteId = UUID(uuidString: remoteIdText),
      let service = uuid(from: args["serviceUuid"]),
      let rx = uuid(from: args["rxUuid"]),
      let tx = uuid(from: args["txUuid"])
    else {
      result(FlutterError(code: "bad_args", message: "Invalid BLE central connect arguments", details: nil))
      return
    }

    serviceUuid = service
    rxUuid = rx
    txUuid = tx
    targetRemoteId = remoteId
    restoreEnabled = args["restoreEnabled"] as? Bool ?? true
    reconnectOnRestore = args["reconnectOnRestore"] as? Bool ?? true
    pendingConnect = result

    if centralManager == nil {
      if restoreEnabled {
        centralManager = CBCentralManager(
          delegate: self,
          queue: DispatchQueue.main,
          options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier]
        )
      } else {
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
      }
    }

    if centralManager?.state == .poweredOn {
      connectToPeripheral(remoteId: remoteId)
    }
  }

  private func connectToPeripheral(remoteId: UUID) {
    guard let manager = centralManager else { return }
    if let current = targetPeripheral, current.identifier == remoteId {
      manager.connect(current, options: nil)
      return
    }
    let peripherals = manager.retrievePeripherals(withIdentifiers: [remoteId])
    guard let peripheral = peripherals.first else {
      pendingConnect?(FlutterError(code: "not_found", message: "BLE peripheral was not found by iOS", details: remoteId.uuidString))
      pendingConnect = nil
      return
    }
    targetPeripheral = peripheral
    peripheral.delegate = self
    manager.connect(peripheral, options: nil)
  }

  private func disconnect() {
    pendingConnect = nil
    completePendingSends(errorCode: "disconnected", message: "BLE central disconnected")
    if let peripheral = targetPeripheral, let manager = centralManager {
      manager.cancelPeripheralConnection(peripheral)
    }
    targetPeripheral = nil
    targetRemoteId = nil
    rxCharacteristic = nil
    txCharacteristic = nil
  }

  private func send(data: Data, result: @escaping FlutterResult) {
    guard let peripheral = targetPeripheral, let rx = rxCharacteristic else {
      result(FlutterError(code: "not_connected", message: "BLE central is not connected", details: nil))
      return
    }
    let writeType: CBCharacteristicWriteType = rx.properties.contains(.writeWithoutResponse)
      ? .withoutResponse
      : .withResponse
    let maxWriteLength = peripheral.maximumWriteValueLength(for: writeType)
    guard data.count <= maxWriteLength else {
      result(FlutterError(code: "frame_too_large", message: "BLE frame exceeds native write limit", details: maxWriteLength))
      return
    }
    if writeType == .withResponse {
      pendingSend.append(result)
    }
    peripheral.writeValue(data, for: rx, type: writeType)
    if writeType == .withoutResponse {
      result(nil)
    }
  }

  private func completePendingSends(errorCode: String, message: String) {
    let sends = pendingSend
    pendingSend.removeAll()
    for send in sends {
      send(FlutterError(code: errorCode, message: message, details: nil))
    }
  }

  private func emit(_ event: [String: Any]) {
    if let eventSink {
      eventSink(event)
    } else {
      bufferedEvents.append(event)
      if bufferedEvents.count > maxBufferedEvents {
        bufferedEvents.removeFirst(bufferedEvents.count - maxBufferedEvents)
      }
    }
  }

  private func flushBufferedEvents() {
    guard let eventSink else { return }
    let events = bufferedEvents
    bufferedEvents.removeAll()
    for event in events {
      eventSink(event)
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

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    emit(["event": "state", "state": central.state.rawValue])
    if central.state == .poweredOn {
      if let targetRemoteId, pendingConnect != nil {
        connectToPeripheral(remoteId: targetRemoteId)
      }
    } else if central.state == .poweredOff {
      pendingConnect?(FlutterError(code: "powered_off", message: "Bluetooth is powered off", details: nil))
      pendingConnect = nil
    } else if central.state == .unsupported {
      pendingConnect?(FlutterError(code: "unsupported", message: "Bluetooth LE central is not supported", details: nil))
      pendingConnect = nil
    } else if central.state == .unauthorized {
      pendingConnect?(FlutterError(code: "unauthorized", message: "Bluetooth permission was not granted", details: nil))
      pendingConnect = nil
    }
  }

  func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
    if let peripheral = restored.first {
      targetPeripheral = peripheral
      peripheral.delegate = self
      emit(["event": "restored", "remoteId": peripheral.identifier.uuidString])
      if reconnectOnRestore {
        central.connect(peripheral, options: nil)
      }
    } else {
      emit(["event": "restored"])
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    targetPeripheral = peripheral
    peripheral.delegate = self
    guard let serviceUuid else {
      pendingConnect?(FlutterError(code: "bad_state", message: "BLE service UUID is missing", details: nil))
      pendingConnect = nil
      return
    }
    emit(["event": "connected", "remoteId": peripheral.identifier.uuidString])
    peripheral.discoverServices([serviceUuid])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    pendingConnect?(FlutterError(code: "connect_failed", message: error?.localizedDescription ?? "BLE connect failed", details: nil))
    pendingConnect = nil
    emit([
      "event": "disconnected",
      "remoteId": peripheral.identifier.uuidString,
      "error": error?.localizedDescription ?? "",
    ])
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    if peripheral.identifier == targetPeripheral?.identifier {
      rxCharacteristic = nil
      txCharacteristic = nil
      completePendingSends(errorCode: "disconnected", message: "BLE central disconnected")
      emit([
        "event": "disconnected",
        "remoteId": peripheral.identifier.uuidString,
        "error": error?.localizedDescription ?? "",
      ])
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let error {
      pendingConnect?(FlutterError(code: "discover_services_failed", message: error.localizedDescription, details: nil))
      pendingConnect = nil
      return
    }
    guard let serviceUuid, let rxUuid, let txUuid else { return }
    for service in peripheral.services ?? [] where service.uuid == serviceUuid {
      peripheral.discoverCharacteristics([rxUuid, txUuid], for: service)
      return
    }
    pendingConnect?(FlutterError(code: "service_not_found", message: "MeshCore UART service not found", details: nil))
    pendingConnect = nil
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let error {
      pendingConnect?(FlutterError(code: "discover_characteristics_failed", message: error.localizedDescription, details: nil))
      pendingConnect = nil
      return
    }
    guard let rxUuid, let txUuid else { return }
    for characteristic in service.characteristics ?? [] {
      if characteristic.uuid == rxUuid {
        rxCharacteristic = characteristic
      } else if characteristic.uuid == txUuid {
        txCharacteristic = characteristic
      }
    }
    guard let tx = txCharacteristic, rxCharacteristic != nil else {
      pendingConnect?(FlutterError(code: "characteristic_not_found", message: "MeshCore UART characteristics not found", details: nil))
      pendingConnect = nil
      return
    }
    peripheral.setNotifyValue(true, for: tx)
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == txUuid else { return }
    if let error {
      pendingConnect?(FlutterError(code: "notify_failed", message: error.localizedDescription, details: nil))
      pendingConnect = nil
      return
    }
    if characteristic.isNotifying {
      pendingConnect?(nil)
      pendingConnect = nil
      emit(["event": "ready", "remoteId": peripheral.identifier.uuidString])
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == txUuid else { return }
    if let error {
      emit(["event": "rx_error", "error": error.localizedDescription])
      return
    }
    guard let value = characteristic.value else { return }
    emit([
      "event": "data",
      "remoteId": peripheral.identifier.uuidString,
      "data": FlutterStandardTypedData(bytes: value),
    ])
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard characteristic.uuid == rxUuid else { return }
    let result = pendingSend.isEmpty ? nil : pendingSend.removeFirst()
    if let error {
      result?(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil))
    } else {
      result?(nil)
    }
  }
}
