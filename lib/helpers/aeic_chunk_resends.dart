import 'dart:convert';
import 'dart:typed_data';

import 'channel_resend_control.dart';

/// Exact channel + blob identity keeps coverage separate for every data/parity
/// packet. No timestamps, headers or image payload bytes change on a retry.
class AeicChunkResends {
  final _packets = <AeicChunkResend>{};

  AeicChunkResend track(int channelIndex, Uint8List blob, {Uint8List? selfKey}) {
    final packet = AeicChunkResend._(channelIndex, blob, selfKey);
    _packets.add(packet);
    return packet;
  }

  void heard(int channelIndex, Uint8List blob, {
    required Uint8List pathBytes,
    required int hopCount,
    required int hashWidth,
  }) {
    final key = base64Encode(blob);
    for (final packet in _packets) {
      if (packet.channelIndex != channelIndex || packet.key != key) {
        continue;
      }
      packet._heard(pathBytes, hopCount, hashWidth);
    }
  }

  void release(AeicChunkResend packet) {
    packet.cancel();
    _packets.remove(packet);
  }

  void cancelAll() {
    for (final packet in _packets) {
      packet.cancel();
    }
    _packets.clear();
  }
}

class AeicChunkResend {
  AeicChunkResend._(this.channelIndex, Uint8List blob, this._selfKey)
      : blob = Uint8List.fromList(blob), key = base64Encode(blob);

  final int channelIndex;
  final Uint8List blob;
  final String key;
  final Uint8List? _selfKey;
  final _control = ChannelResendControl(minHops: 0);
  final _firstHops = <String>{};
  int _maxHops = 0;
  int get maxHops => _maxHops;
  int get distinctRepeaters => _firstHops.length;
  bool get cancelled => _control.cancelled;

  bool satisfied({required int minHops, required bool countRepeaters,
    required int minRepeaters}) => _maxHops >= minHops ||
      (countRepeaters && _firstHops.length >= minRepeaters);

  void _heard(Uint8List path, int hops, int width) {
    if (cancelled || width < 1 || width > 3 || hops <= 0 ||
        path.length < hops * width) {
      return;
    }
    if (hops > _maxHops) _maxHops = hops;
    final first = base64Encode(path.sublist(0, width));
    final self = _selfKey;
    if (self == null || self.length < width ||
        first != base64Encode(self.sublist(0, width))) {
      _firstHops.add('$width:$first');
    }
    _control.wake();
  }

  void cancel() => _control.cancel();

  /// Listening never holds the radio's scope lock. Echo wakeups retain the
  /// original deadline unless coverage is sufficient. A queued sender must
  /// also recheck [canContinue] and [isSatisfied] immediately before writing.
  Future<void> watch({
    required int maxResends,
    required Duration Function() delay,
    required DateTime Function() now,
    required bool Function() canContinue,
    required bool Function() isSatisfied,
    required Future<void> Function(int retry) resend,
  }) async {
    for (var attempt = 0; ; attempt++) {
      final deadline = now().add(delay());
      while (!cancelled && canContinue() && !isSatisfied()) {
        final remaining = deadline.difference(now());
        if (remaining <= Duration.zero) {
          break;
        }
        await _control.wait(remaining);
      }
      if (cancelled || !canContinue() || isSatisfied() || attempt >= maxResends) {
        return;
      }
      await resend(attempt + 1);
    }
  }
}
