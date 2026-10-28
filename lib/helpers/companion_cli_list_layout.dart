import 'companion_cli_protocol.dart';

/// null — служебная строка. Исходные типы channel/group/peer не меняются.
class CompanionCliListLayout<T extends Object> {
  CompanionCliListLayout({required List<T> items, required this.keyOf,
    required this.previousOrder, required this.visible,
    this.retainPeerKeys = false, this.minimumPosition = 0}) : entries = [...items] {
    if (visible) {
      entries.insert(_savedPosition(items).clamp(minimumPosition, entries.length).toInt(), null);
    }
  }
  final String Function(T) keyOf;
  final List<String> previousOrder;
  final bool visible;
  final bool retainPeerKeys;
  final int minimumPosition;
  final List<T?> entries;

  int _savedPosition(List<T> normal) {
    final index = previousOrder.indexOf(companionCliOrderKey);
    if (index < 0) {
      return 0;
    }
    final keys = normal.map(keyOf).toSet();
    return previousOrder.take(index).where(keys.contains).length;
  }

  List<T?> moved(int oldIndex, int newIndex) {
    final next = List<T?>.of(entries);
    next.insert(newIndex, next.removeAt(oldIndex));
    final service = next.indexOf(null);
    if (service >= 0 && service < minimumPosition) {
      next.removeAt(service);
      next.insert(minimumPosition, null);
    }
    return next;
  }

  /// Восстанавливает обычный unread-порядок существующим алгоритмом и отдельно
  /// сохраняет service position, в том числе пока строка скрыта переключателем.
  List<String> order(List<T?> moved, List<T> normal) {
    final next = normal.map(keyOf).toList();
    final saved = previousOrder.contains(companionCliOrderKey);
    final index = visible ? moved.indexOf(null) : (saved ? _savedPosition(normal) : -1);
    if (index >= 0) {
      next.insert(index.clamp(0, next.length).toInt(), companionCliOrderKey);
    }
    if (retainPeerKeys) {
      for (var i = 0; i < previousOrder.length; i++) {
        final key = previousOrder[i];
        if (key.startsWith('peer:') && !next.contains(key)) {
          next.insert(i.clamp(0, next.length).toInt(), key);
        }
      }
    }
    return next;
  }
}
