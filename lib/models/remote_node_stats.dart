import 'dart:typed_data';

/// Binary status reply pushed as PUSH_CODE_STATUS_RESPONSE.
///
/// The first 48 bytes are shared by repeater `RepeaterStats` and room
/// `ServerStats`. After that, repeaters send `total_rx_air_time_secs` and
/// `n_recv_errors` (uint32 each), rooms send `n_posted` and `n_post_push`
/// (uint16 each).
class RemoteNodeStats {
  static const int payloadOffset = 8;
  static const int commonSize = 48;

  final int batteryMv;
  final int queueLen;
  final int noiseFloor;
  final int lastRssi;
  final int packetsRecv;
  final int packetsSent;
  final int txAirSecs;
  final int uptimeSecs;
  final int floodTx;
  final int directTx;
  final int floodRx;
  final int directRx;
  final int errEvents;
  final double lastSnr;
  final int directDups;
  final int floodDups;
  final int? rxAirSecs;
  final int? recvErrors;
  final int? posted;
  final int? postPushes;

  const RemoteNodeStats({
    required this.batteryMv,
    required this.queueLen,
    required this.noiseFloor,
    required this.lastRssi,
    required this.packetsRecv,
    required this.packetsSent,
    required this.txAirSecs,
    required this.uptimeSecs,
    required this.floodTx,
    required this.directTx,
    required this.floodRx,
    required this.directRx,
    required this.errEvents,
    required this.lastSnr,
    required this.directDups,
    required this.floodDups,
    this.rxAirSecs,
    this.recvErrors,
    this.posted,
    this.postPushes,
  });

  static RemoteNodeStats? tryParse(Uint8List frame, {required bool isRoom}) {
    if (frame.length < payloadOffset + commonSize) return null;
    final data = ByteData.sublistView(frame, payloadOffset);
    int u16(int o) => data.getUint16(o, Endian.little);
    int i16(int o) => data.getInt16(o, Endian.little);
    int u32(int o) => data.getUint32(o, Endian.little);
    bool has(int o, int size) => data.lengthInBytes >= o + size;

    return RemoteNodeStats(
      batteryMv: u16(0),
      queueLen: u16(2),
      noiseFloor: i16(4),
      lastRssi: i16(6),
      packetsRecv: u32(8),
      packetsSent: u32(12),
      txAirSecs: u32(16),
      uptimeSecs: u32(20),
      floodTx: u32(24),
      directTx: u32(28),
      floodRx: u32(32),
      directRx: u32(36),
      errEvents: u16(40),
      lastSnr: i16(42) / 4.0,
      directDups: u16(44),
      floodDups: u16(46),
      rxAirSecs: !isRoom && has(48, 4) ? u32(48) : null,
      recvErrors: !isRoom && has(52, 4) ? u32(52) : null,
      posted: isRoom && has(48, 2) ? u16(48) : null,
      postPushes: isRoom && has(50, 2) ? u16(50) : null,
    );
  }
}
