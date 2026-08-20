import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';

/// Describes the temporary map focus used by the repeater-neighbors screen.
///
/// Keeping the matching and geometry here leaves the general map with only a
/// few integration hooks and avoids storing this transient view in wardrive.
class NeighborMapFocus {
  final String repeaterKey;
  final Set<String> neighborKeys;

  NeighborMapFocus({
    required String repeaterKey,
    required Iterable<String> neighborKeys,
  }) : repeaterKey = repeaterKey.toLowerCase(),
       neighborKeys = Set.unmodifiable(
         neighborKeys.map((key) => key.toLowerCase()),
       );

  int get signature => Object.hash(
    repeaterKey,
    Object.hashAllUnordered(neighborKeys),
  );

  bool contains(Contact contact) {
    if (publicKeysMatch(contact.publicKeyHex, repeaterKey)) return true;
    return neighborKeys.any(
      (key) => publicKeysMatch(contact.publicKeyHex, key),
    );
  }

  double opacityFor(Contact contact) {
    if (contact.type != advTypeRepeater) return 1.0;
    return contains(contact) ? 1.0 : 0.3;
  }

  List<Contact> mergeVisibleContacts({
    required Iterable<Contact> currentlyVisible,
    required Iterable<Contact> mapContacts,
    required Iterable<Contact> allContacts,
  }) {
    final result = List<Contact>.of(currentlyVisible);
    final includedKeys = result
        .map((contact) => contact.publicKeyHex.toLowerCase())
        .toSet();

    void addIfMissing(Contact contact) {
      if (!contact.hasLocation || contact.type != advTypeRepeater) return;
      if (includedKeys.add(contact.publicKeyHex.toLowerCase())) {
        result.add(contact);
      }
    }

    for (final contact in mapContacts) {
      addIfMissing(contact);
    }
    for (final contact in allContacts.where(contains)) {
      addIfMissing(contact);
    }
    return result;
  }

  List<Contact> locatedContacts(Iterable<Contact> contacts) {
    return contacts
        .where(
          (contact) =>
              contact.type == advTypeRepeater &&
              contact.hasLocation &&
              contains(contact),
        )
        .toList(growable: false);
  }

  List<LatLng> points(Iterable<Contact> contacts) {
    return locatedContacts(contacts)
        .map((contact) => LatLng(contact.latitude!, contact.longitude!))
        .toList(growable: false);
  }

  LatLng? center(Iterable<Contact> contacts) {
    final focusPoints = points(contacts);
    if (focusPoints.isEmpty) return null;

    var latitude = 0.0;
    var longitude = 0.0;
    for (final point in focusPoints) {
      latitude += point.latitude;
      longitude += point.longitude;
    }
    return LatLng(
      latitude / focusPoints.length,
      longitude / focusPoints.length,
    );
  }

  List<Polyline> buildPolylines(
    Iterable<Contact> contacts, {
    required Color color,
    double strokeWidth = 2.5,
  }) {
    Contact? repeater;
    for (final contact in contacts) {
      if (contact.type == advTypeRepeater &&
          contact.hasLocation &&
          publicKeysMatch(contact.publicKeyHex, repeaterKey)) {
        repeater = contact;
        break;
      }
    }
    if (repeater == null || neighborKeys.isEmpty) {
      return const <Polyline>[];
    }

    final repeaterPoint = LatLng(repeater.latitude!, repeater.longitude!);
    return contacts
        .where(
          (contact) =>
              contact.type == advTypeRepeater &&
              contact.hasLocation &&
              neighborKeys.any(
                (key) => publicKeysMatch(contact.publicKeyHex, key),
              ),
        )
        .map(
          (neighbor) => Polyline(
            points: [
              LatLng(neighbor.latitude!, neighbor.longitude!),
              repeaterPoint,
            ],
            strokeWidth: strokeWidth,
            color: color,
          ),
        )
        .toList(growable: false);
  }

  static bool publicKeysMatch(String first, String second) {
    final firstKey = first.toLowerCase();
    final secondKey = second.toLowerCase();
    if (firstKey == secondKey) return true;
    final shortest = min(firstKey.length, secondKey.length);
    if (shortest < 8) return false;
    return firstKey.startsWith(secondKey) || secondKey.startsWith(firstKey);
  }
}
