import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import 'path_helper.dart';

typedef ManualTraceInput = ({Uint8List bytes, int width});

final _separators = RegExp(r'[,\s>→/\-]+');
final _hex = RegExp(r'^[a-fA-F0-9]+$');

/// A continuous hex string uses the radio width. Separated hashes declare
/// their own width and must all match so a typo cannot drop a hop silently.
ManualTraceInput? parseManualTrace(String text, int defaultWidth) {
  final tokens = [
    for (final token in text.trim().split(_separators))
      if (token.isNotEmpty)
        token.startsWith('0x') || token.startsWith('0X')
            ? token.substring(2)
            : token,
  ];
  if (tokens.isEmpty) return null;
  final width = tokens.length == 1
      ? defaultWidth.clamp(1, maxPathHashWidth)
      : tokens.first.length ~/ 2;
  if (width < 1 || width > maxPathHashWidth) return null;
  final charsPerHop = width * 2;
  final bytes = <int>[];
  for (final token in tokens) {
    if (token.length % charsPerHop != 0 ||
        (tokens.length > 1 && token.length != charsPerHop) ||
        !_hex.hasMatch(token)) {
      return null;
    }
    for (var i = 0; i < token.length; i += 2) {
      bytes.add(int.parse(token.substring(i, i + 2), radix: 16));
    }
  }
  return (bytes: Uint8List.fromList(bytes), width: width);
}

/// A 3-byte hop needs the fourth byte from an unambiguous public key.
/// Shorter hops can be sent without a contact and keep their hex label.
List<Contact>? resolveManualTraceContacts(
  ManualTraceInput input,
  Iterable<Contact> contacts,
) {
  final prefixes = {
    for (final hop in PathHelper.splitPathBytes(input.bytes, input.width))
      PathHelper.formatHopHex(hop),
  };
  final matches = <String, Contact>{};
  final ambiguous = <String>{};
  for (final contact in contacts) {
    if (contact.type == advTypeChat ||
        contact.publicKey.length < (input.width == 3 ? 4 : input.width)) {
      continue;
    }
    final prefix = contact.publicKeyPrefixHex(input.width);
    if (!prefixes.contains(prefix) || ambiguous.contains(prefix)) continue;
    final previous = matches[prefix];
    if (previous == null) {
      matches[prefix] = contact;
    } else if (previous.publicKeyHex != contact.publicKeyHex) {
      matches.remove(prefix);
      ambiguous.add(prefix);
    }
  }
  if (input.width == 3 && matches.length != prefixes.length) return null;
  return matches.values.toList(growable: false);
}
