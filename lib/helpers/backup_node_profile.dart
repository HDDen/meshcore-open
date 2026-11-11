import 'dart:convert';

import '../connector/meshcore_protocol.dart';

enum BackupNodeProfilePart { nodeName, position, privacy }

typedef BackupNodePosition = ({int latitudeE6, int longitudeE6});
typedef BackupNodePrivacy = ({
  int? telemetryBase,
  int? telemetryLocation,
  int? telemetryEnvironment,
  int? advertLocation,
  int? multiAcks,
});

class BackupNodeProfile {
  const BackupNodeProfile({this.nodeName, this.position, this.privacy});

  factory BackupNodeProfile.fromBackup({
    Object? name,
    Map<String, Object?>? position,
    Map<String, Object?>? privacy,
  }) {
    if (name != null && (name is! String || !validName(name))) {
      throw const FormatException('Invalid backup node name');
    }
    final latitude = position?['latitude'];
    final longitude = position?['longitude'];
    final coordinates = latitude == null && longitude == null
        ? null : readPosition(latitude, longitude);
    if (coordinates == null && (latitude != null || longitude != null)) {
      throw const FormatException('Invalid backup node coordinates');
    }
    int? readOption(String key, int maximum) {
      final value = privacy?[key];
      if (value == null) return null;
      if (value is! int || value < 0 || value > maximum) {
        throw const FormatException('Invalid backup node privacy setting');
      }
      return value;
    }
    final settings = (
      telemetryBase: readOption('telemetryBase', teleModeAllowAll),
      telemetryLocation: readOption('telemetryLocation', teleModeAllowAll),
      telemetryEnvironment: readOption('telemetryEnvironment', teleModeAllowAll),
      advertLocation: readOption('advertLocation', 1),
      multiAcks: readOption('multiAcks', 2),
    );
    return BackupNodeProfile(
      nodeName: name as String?,
      position: coordinates,
      privacy: privacyValues(settings).isEmpty ? null : settings,
    );
  }

  static bool validName(String name) => name.trim().isNotEmpty &&
      !name.contains('\u0000') && utf8.encode(name).length < maxNameSize;

  static BackupNodePosition? readPosition(Object? latitude, Object? longitude) {
    if (latitude is! num || longitude is! num || !latitude.isFinite ||
        !longitude.isFinite || latitude.abs() > 90 || longitude.abs() > 180) {
      return null;
    }
    return (
      latitudeE6: (latitude * 1000000).round(),
      longitudeE6: (longitude * 1000000).round(),
    );
  }

  static Map<String, int> privacyValues(BackupNodePrivacy privacy) => {
    'telemetryBase': ?privacy.telemetryBase,
    'telemetryLocation': ?privacy.telemetryLocation,
    'telemetryEnvironment': ?privacy.telemetryEnvironment,
    'advertLocation': ?privacy.advertLocation,
    'multiAcks': ?privacy.multiAcks,
  };

  final String? nodeName;
  final BackupNodePosition? position;
  final BackupNodePrivacy? privacy;
  bool get isEmpty => nodeName == null && position == null && privacy == null;

  Object? value(BackupNodeProfilePart part) => switch (part) {
    BackupNodeProfilePart.nodeName => nodeName,
    BackupNodeProfilePart.position => position,
    BackupNodeProfilePart.privacy => privacy,
  };

  BackupNodeProfile changesFrom(BackupNodeProfile current) {
    final before = current.privacy;
    final after = privacy;
    final merged = before == null || after == null ? null : (
      telemetryBase: after.telemetryBase ?? before.telemetryBase,
      telemetryLocation: after.telemetryLocation ?? before.telemetryLocation,
      telemetryEnvironment: after.telemetryEnvironment ?? before.telemetryEnvironment,
      advertLocation: after.advertLocation ?? before.advertLocation,
      multiAcks: after.multiAcks ?? before.multiAcks,
    );
    return BackupNodeProfile(
      nodeName: nodeName == current.nodeName ? null : nodeName,
      position: position == current.position ? null : position,
      privacy: merged == before ? null : merged,
    );
  }
}

class BackupNodeProfilePreview {
  BackupNodeProfilePreview({
    required this.session,
    required this.nodeKey,
    required this.before,
    required BackupNodeProfile source,
    required this.manualAddContactFlags,
  }) : changes = source.changesFrom(before);

  final Object session;
  final String nodeKey;
  final BackupNodeProfile before;
  final BackupNodeProfile changes;
  final int manualAddContactFlags;
}

enum BackupNodeProfileStatus { completed, destinationChanged, writeUnconfirmed }

typedef BackupNodeProfileResult = ({int confirmed, BackupNodeProfileStatus status});
