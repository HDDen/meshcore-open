import Foundation
import Network
import NetworkExtension
import UserNotifications

final class MeshCoreBackgroundTcpProvider: NEAppPushProvider {
  private let queue = DispatchQueue(label: "mco.background.tcp")
  private var connection: NWConnection?
  private var rxBuffer: [UInt8] = []
  private var startCompletion: ((Error?) -> Void)?
  private var startCompletionFinished = false

  private let txFrameStart: UInt8 = 0x3c
  private let rxFrameStart: UInt8 = 0x3e
  private let maxPayloadLength = 176

  private let cmdAppStart: UInt8 = 1
  private let cmdSyncNextMessage: UInt8 = 10
  private let cmdDeviceQuery: UInt8 = 22
  private let appProtocolVersion: UInt8 = 4
  private let respCodeContactMsgRecv: UInt8 = 7
  private let respCodeChannelMsgRecv: UInt8 = 8
  private let respCodeContactMsgRecvV3: UInt8 = 16
  private let respCodeChannelMsgRecvV3: UInt8 = 17
  private let respCodeChannelDataRecv: UInt8 = 27
  private let pushCodeMsgWaiting: UInt8 = 0x83
  private let pushCodeLoginSuccess: UInt8 = 0x85
  private let pushCodeLoginFail: UInt8 = 0x86
  private let txtTypePlain: UInt8 = 0
  private let txtTypeSigned: UInt8 = 2

  override func start() {
    startConnection(completionHandler: { _ in })
  }

  override func start(completionHandler: @escaping (Error?) -> Void) {
    startConnection(completionHandler: completionHandler)
  }

  override func stop(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    queue.async { [weak self] in
      self?.connection?.cancel()
      self?.connection = nil
      self?.rxBuffer.removeAll(keepingCapacity: false)
      completionHandler()
    }
  }

  override func handleTimerEvent() {
    queue.async { [weak self] in
      self?.sendAppStart()
    }
  }

  private func startConnection(completionHandler: @escaping (Error?) -> Void) {
    guard let config = providerConfiguration,
          let host = config["host"] as? String,
          let portValue = config["port"] as? Int,
          let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
      completionHandler(NSError(domain: "MeshCoreBackgroundTcp", code: 1))
      return
    }

    let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
    self.connection = connection
    startCompletion = completionHandler
    startCompletionFinished = false
    NSLog("MCO background TCP: provider starting endpoint=\(host):\(portValue)")

    connection.stateUpdateHandler = { [weak self] state in
      guard let self = self else { return }
      switch state {
      case .ready:
        NSLog("MCO background TCP: provider ready")
        self.finishStart(nil)
        self.sendDeviceQuery()
        self.sendAppStart()
        self.receiveLoop()
      case .failed(let error):
        NSLog("MCO background TCP: provider failed: \(error.localizedDescription)")
        self.finishStart(error)
        self.connection?.cancel()
      case .cancelled:
        NSLog("MCO background TCP: provider cancelled")
        self.finishStart(nil)
      default:
        break
      }
    }
    connection.start(queue: queue)
  }

  private func finishStart(_ error: Error?) {
    guard !startCompletionFinished else { return }
    startCompletionFinished = true
    startCompletion?(error)
    startCompletion = nil
  }

  private func sendAppStart() {
    let appName = (providerConfiguration?["appName"] as? String) ?? "MeshCoreOpen;cap=mctxt,mcmp,aeic"
    var payload: [UInt8] = [cmdAppStart, 1, 0, 0, 0, 0, 0, 0]
    payload.append(contentsOf: appName.utf8)
    payload.append(0)
    sendFrame(payload)
  }

  private func sendDeviceQuery() {
    sendFrame([cmdDeviceQuery, appProtocolVersion])
  }

  private func sendSyncNextMessage() {
    sendFrame([cmdSyncNextMessage])
  }

  private func sendFrame(_ payload: [UInt8]) {
    guard payload.count <= maxPayloadLength, let connection = connection else { return }
    var packet: [UInt8] = [
      txFrameStart,
      UInt8(payload.count & 0xff),
      UInt8((payload.count >> 8) & 0xff)
    ]
    packet.append(contentsOf: payload)
    connection.send(content: Data(packet), completion: .contentProcessed { _ in })
  }

  private func receiveLoop() {
    connection?.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, isComplete, error in
      guard let self = self else { return }
      if let data = data, !data.isEmpty {
        self.ingest(Array(data))
      }
      if error == nil && !isComplete {
        self.receiveLoop()
      }
    }
  }

  private func ingest(_ bytes: [UInt8]) {
    rxBuffer.append(contentsOf: bytes)
    while true {
      guard let start = rxBuffer.firstIndex(where: { $0 == rxFrameStart || $0 == txFrameStart }) else {
        rxBuffer.removeAll(keepingCapacity: true)
        return
      }
      if start > 0 {
        rxBuffer.removeFirst(start)
      }
      guard rxBuffer.count >= 3 else { return }
      let length = Int(rxBuffer[1]) | (Int(rxBuffer[2]) << 8)
      if length > maxPayloadLength {
        rxBuffer.removeFirst()
        continue
      }
      guard rxBuffer.count >= 3 + length else { return }
      let frameStart = rxBuffer[0]
      let payload = Array(rxBuffer[3..<(3 + length)])
      rxBuffer.removeFirst(3 + length)
      if frameStart == rxFrameStart {
        handlePayload(payload)
      }
    }
  }

  private func handlePayload(_ payload: [UInt8]) {
    guard let code = payload.first else { return }
    NSLog("MCO background TCP: RX code=\(code) len=\(payload.count)")
    if code == pushCodeMsgWaiting {
      sendSyncNextMessage()
      return
    }
    if code == pushCodeLoginSuccess || code == pushCodeLoginFail {
      return
    }
    if let notification = parseContactMessage(payload) ?? parseChannelMessage(payload) ?? parseChannelData(payload) {
      showNotification(title: notification.title, body: notification.body)
      sendSyncNextMessage()
    } else if isLikelyMessagePayload(payload) {
      showNotification(title: "MeshCore", body: "New MeshCore message")
      sendSyncNextMessage()
    }
  }

  private func isLikelyMessagePayload(_ payload: [UInt8]) -> Bool {
    guard let code = payload.first else { return false }
    return code == respCodeContactMsgRecv ||
      code == respCodeChannelMsgRecv ||
      code == respCodeContactMsgRecvV3 ||
      code == respCodeChannelMsgRecvV3 ||
      code == respCodeChannelDataRecv
  }

  private func parseContactMessage(_ frame: [UInt8]) -> (title: String, body: String)? {
    guard let code = frame.first,
          code == respCodeContactMsgRecv || code == respCodeContactMsgRecvV3 else {
      return nil
    }
    var offset = 1
    if code == respCodeContactMsgRecvV3 {
      offset += 3
    }
    guard frame.count >= offset + 6 + 1 + 1 + 4 else { return nil }
    offset += 6
    offset += 1
    let textType = frame[offset]
    offset += 1
    offset += 4
    let shiftedType = textType >> 2
    let isSigned = shiftedType == txtTypeSigned || textType == txtTypeSigned
    if isSigned {
      guard frame.count >= offset + 4 else { return nil }
      offset += 4
    } else if shiftedType != txtTypePlain && textType != txtTypePlain {
      return nil
    }
    guard let text = decodeText(Array(frame[offset..<frame.count])), !text.isEmpty else {
      return nil
    }
    return ("MeshCore", text)
  }

  private func parseChannelMessage(_ frame: [UInt8]) -> (title: String, body: String)? {
    guard let code = frame.first,
          code == respCodeChannelMsgRecv || code == respCodeChannelMsgRecvV3 else {
      return nil
    }
    var offset = 1
    let channelIndex: UInt8
    let textType: UInt8

    if code == respCodeChannelMsgRecvV3 {
      guard frame.count >= 6 else { return nil }
      offset += 1
      let flags = frame[offset]
      offset += 1
      offset += 1
      channelIndex = frame[offset]
      offset += 1
      let pathByte = frame[offset]
      offset += 1
      if pathByte != 0xff && (flags & 0x01) != 0 {
        let pathHashWidth = Int((pathByte & 0xc0) >> 6) + 1
        let hopCount = Int(pathByte & 0x3f)
        offset += pathHashWidth * hopCount
      }
      guard frame.count > offset else { return nil }
      textType = frame[offset]
      offset += 1
    } else {
      guard frame.count >= 4 else { return nil }
      channelIndex = frame[offset]
      offset += 1
      offset += 1
      textType = frame[offset]
      offset += 1
    }

    guard textType == txtTypePlain, frame.count >= offset + 4 else { return nil }
    offset += 4
    guard let text = decodeText(Array(frame[offset..<frame.count])), !text.isEmpty else {
      return nil
    }
    let (sender, body) = splitSenderText(text)
    return ("Channel \(channelIndex)", sender == nil ? body : "\(sender!): \(body)")
  }

  private func parseChannelData(_ frame: [UInt8]) -> (title: String, body: String)? {
    guard let code = frame.first, frame.count >= 9, code == respCodeChannelDataRecv else {
      return nil
    }
    let channelIndex = frame[4]
    let dataType = Int(frame[6]) | (Int(frame[7]) << 8)
    let dataLength = Int(frame[8])
    guard dataLength <= frame.count - 9 else { return nil }
    return ("Channel \(channelIndex)", "New channel data message (\(dataType))")
  }

  private func decodeText(_ bytes: [UInt8]) -> String? {
    let textBytes = bytes.prefix { $0 != 0 }
    if let text = String(bytes: textBytes, encoding: .utf8) {
      return text
    }
    return String(bytes: textBytes, encoding: .isoLatin1)
  }

  private func splitSenderText(_ text: String) -> (String?, String) {
    guard let colonIndex = text.firstIndex(of: ":") else {
      return (nil, text)
    }
    let sender = String(text[..<colonIndex])
    guard !sender.isEmpty, sender.count < 50, !sender.contains("[") else {
      return (nil, text)
    }
    var bodyStart = text.index(after: colonIndex)
    if bodyStart < text.endIndex && text[bodyStart] == " " {
      bodyStart = text.index(after: bodyStart)
    }
    return (sender, String(text[bodyStart...]))
  }

  private func showNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "mco.background.tcp.\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { [weak self] error in
      if let error = error {
        NSLog("MCO background TCP: failed to show extension notification: \(error.localizedDescription)")
        self?.reportNotificationToManager(title: title, body: body)
      } else {
        NSLog("MCO background TCP: extension notification scheduled")
      }
    }
  }

  private func reportNotificationToManager(title: String, body: String) {
    reportIncomingCall(userInfo: [
      "kind": "meshcore.background.tcp.message",
      "title": title,
      "body": body
    ])
  }
}
