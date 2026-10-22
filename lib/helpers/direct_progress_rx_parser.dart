import 'dart:typed_data';

/// Пропускает только разбор прогресса, если сервису нечего отслеживать.
class DirectProgressRxParser<T> {
  DirectProgressRxParser(T? Function(Uint8List) parseFrame)
      : _parseFrame = parseFrame;

  final T? Function(Uint8List) _parseFrame;
  bool _enabled = false;

  void setEnabled(bool enabled) => _enabled = enabled;

  T? parse(Uint8List frame, {required bool hasTrackers}) {
    if (_enabled && !hasTrackers) {
      return null;
    }
    return _parseFrame(frame);
  }
}
