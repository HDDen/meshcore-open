import 'package:flutter/material.dart';

import '../connector/meshcore_protocol.dart';
import '../utils/emoji_utils.dart';

IconData contactTypeIcon(int type) {
  switch (type) {
    case advTypeChat:
      return Icons.chat;
    case advTypeRepeater:
      return Icons.cell_tower;
    case advTypeRoom:
      return Icons.group;
    case advTypeSensor:
      return Icons.sensors;
    default:
      return Icons.device_unknown;
  }
}

Color contactTypeColor(int type) {
  switch (type) {
    case advTypeChat:
      return Colors.blue;
    case advTypeRepeater:
      return Colors.orange;
    case advTypeRoom:
      return Colors.purple;
    case advTypeSensor:
      return Colors.green;
    default:
      return Colors.grey;
  }
}

Color colorForName(String name) {
  const colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
    Colors.cyan,
    Colors.amber,
    Colors.deepOrange,
  ];
  return colors[name.hashCode.abs() % colors.length];
}

String firstCharacterOrEmoji(String name) {
  if (name.isEmpty) return '?';
  final emoji = firstEmoji(name);
  if (emoji != null) return emoji;
  final runes = name.runes.toList();
  if (runes.isEmpty) return '?';
  return String.fromCharCode(runes[0]).toUpperCase();
}
