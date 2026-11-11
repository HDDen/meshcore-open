import 'dart:convert';

import '../connector/meshcore_protocol.dart';

enum BackupNodeProfilePart {
  nodeName,
  position,
  privacy,
  tuning,
  txPower,
  pathHashWidth,
  defaultFloodScope;

  static const radio = [tuning, txPower, pathHashWidth, defaultFloodScope];
}

typedef BackupNodePosition = ({int latitudeE6, int longitudeE6});
typedef BackupNodePrivacy = ({
  int? telemetryBase,
  int? telemetryLocation,
  int? telemetryEnvironment,
  int? advertLocation,
  int? multiAcks,
});
typedef BackupRadioTuning = ({
  int frequencyKHz,
  int bandwidthHz,
  int spreadingFactor,
  int codingRate,
  bool? clientRepeat,
});

class BackupNodeProfile {
  const BackupNodeProfile({
    this.nodeName,
    this.position,
    this.privacy,
    this.tuning,
    this.txPowerDbm,
    this.pathHashByteWidth,
    this.defaultFloodScope,
  });

  factory BackupNodeProfile.fromBackup({
    Object? name,
    Map<String, Object?>? position,
    Map<String, Object?>? privacy,
    Map<String, Object?>? radio,
    bool officialRadio = false,
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
    final frequency = radio?[officialRadio ? 'frequency' : 'frequencyHz'];
    final bandwidth = radio?[officialRadio ? 'bandwidth' : 'bandwidthHz'];
    final spreading = radio?[officialRadio ? 'spreading_factor' : 'spreadingFactor'];
    final coding = radio?[officialRadio ? 'coding_rate' : 'codingRate'];
    final repeat = officialRadio ? null : radio?['clientRepeat'];
    final txPower = radio?[officialRadio ? 'tx_power' : 'txPowerDbm'];
    final width = officialRadio ? null : radio?['pathHashByteWidth'];
    BackupRadioTuning? tuning;
    if (frequency != null && bandwidth != null && spreading != null && coding != null) {
      tuning = readRadioTuning(
        frequencyKHz: _readFrequencyKHz(frequency, official: officialRadio),
        bandwidthHz: _wholeNumber(bandwidth),
        spreadingFactor: _wholeNumber(spreading),
        codingRate: _wholeNumber(coding),
        clientRepeat: repeat is bool ? repeat : null,
      );
      if (tuning == null || (repeat != null && repeat is! bool)) {
        throw const FormatException('Invalid backup radio parameters');
      }
    }
    final txPowerDbm = _wholeNumber(txPower);
    final pathHashByteWidth = _wholeNumber(width);
    if ((txPower != null && (txPowerDbm == null || txPowerDbm < -9 || txPowerDbm > 127)) ||
        (width != null && (pathHashByteWidth == null || pathHashByteWidth < 1 || pathHashByteWidth > 3))) {
      throw const FormatException('Invalid backup radio option');
    }
    return BackupNodeProfile(
      nodeName: name as String?,
      position: coordinates,
      privacy: privacyValues(settings).isEmpty ? null : settings,
      tuning: tuning,
      txPowerDbm: txPowerDbm,
      pathHashByteWidth: pathHashByteWidth,
      defaultFloodScope: officialRadio ? null : _readDefaultFloodScope(radio),
    );
  }

  static DefaultFloodScope? _readDefaultFloodScope(Map<String, Object?>? radio) {
    final name = radio?['defaultFloodScope'];
    final key = radio?['defaultFloodScopeKey'];
    if (name == null && key == null) return null;
    const invalidScope = FormatException('Invalid backup default flood scope');
    if (name is! String || (key != null && key is! String)) throw invalidScope;
    if (key is String) {
      final scope = (name: name, keyHex: key.toLowerCase());
      if (!isValidDefaultFloodScope(scope)) throw invalidScope;
      return scope;
    }
    if (name.isNotEmpty && name.trim().isEmpty) throw invalidScope;
    try {
      return defaultFloodScopeForRegion(name);
    } on ArgumentError {
      throw invalidScope;
    }
  }

  static int? _wholeNumber(Object? value) =>
      value is num && value.isFinite && value == value.toInt() ? value.toInt() : null;

  static int? _readFrequencyKHz(Object frequency, {required bool official}) {
    if (frequency is! num || !frequency.isFinite) return null;
    // The v1 key says Hz, but existing MeshCore Open files use wire kHz.
    // Official exports converted by upstream can also contain Hz.
    if (frequency >= 150000000 && frequency <= 2500000000) {
      return _wholeNumber(frequency / 1000);
    }
    if (official && frequency >= 150 && frequency <= 2500) {
      final kHz = (frequency * 1000).round();
      return kHz / 1000 == frequency ? kHz : null;
    }
    return _wholeNumber(frequency);
  }

  static BackupRadioTuning? readRadioTuning({
    required int? frequencyKHz,
    required int? bandwidthHz,
    required int? spreadingFactor,
    required int? codingRate,
    required bool? clientRepeat,
  }) {
    if (frequencyKHz == null || frequencyKHz < 150000 || frequencyKHz > 2500000 ||
        bandwidthHz == null || bandwidthHz < 7000 || bandwidthHz > 500000 ||
        spreadingFactor == null || spreadingFactor < 5 || spreadingFactor > 12 ||
        codingRate == null || codingRate < 5 || codingRate > 8) {
      return null;
    }
    return (
      frequencyKHz: frequencyKHz,
      bandwidthHz: bandwidthHz,
      spreadingFactor: spreadingFactor,
      codingRate: codingRate,
      clientRepeat: clientRepeat,
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
  final BackupRadioTuning? tuning;
  final int? txPowerDbm;
  final int? pathHashByteWidth;
  final DefaultFloodScope? defaultFloodScope;

  bool get isEmpty => BackupNodeProfilePart.values.every((part) => value(part) == null);

  Map<String, Object> get radioValues => {
    if (tuning case final radio?) ...{
      'frequencyHz': radio.frequencyKHz,
      'bandwidthHz': radio.bandwidthHz,
      'spreadingFactor': radio.spreadingFactor,
      'codingRate': radio.codingRate,
      'clientRepeat': ?radio.clientRepeat,
    },
    'txPowerDbm': ?txPowerDbm,
    'pathHashByteWidth': ?pathHashByteWidth,
    if (defaultFloodScope case final scope?) ...{
      'defaultFloodScope': scope.name,
      if (scope.name.isNotEmpty) 'defaultFloodScopeKey': scope.keyHex,
    },
  };

  Object? value(BackupNodeProfilePart part) => switch (part) {
    BackupNodeProfilePart.nodeName => nodeName,
    BackupNodeProfilePart.position => position,
    BackupNodeProfilePart.privacy => privacy,
    BackupNodeProfilePart.tuning => tuning,
    BackupNodeProfilePart.txPower => txPowerDbm,
    BackupNodeProfilePart.pathHashWidth => pathHashByteWidth,
    BackupNodeProfilePart.defaultFloodScope => defaultFloodScope,
  };

  BackupNodeProfile changesFrom(
    BackupNodeProfile current,
    Set<BackupNodeProfilePart> unavailable,
  ) {
    final before = current.privacy;
    final after = privacy;
    final merged = before == null || after == null ? null : (
      telemetryBase: after.telemetryBase ?? before.telemetryBase,
      telemetryLocation: after.telemetryLocation ?? before.telemetryLocation,
      telemetryEnvironment: after.telemetryEnvironment ?? before.telemetryEnvironment,
      advertLocation: after.advertLocation ?? before.advertLocation,
      multiAcks: after.multiAcks ?? before.multiAcks,
    );
    final radio = tuning;
    final currentRadio = current.tuning;
    final mergedRadio = radio == null || currentRadio == null ? null : (
      frequencyKHz: radio.frequencyKHz,
      bandwidthHz: radio.bandwidthHz,
      spreadingFactor: radio.spreadingFactor,
      codingRate: radio.codingRate,
      clientRepeat: currentRadio.clientRepeat == null
          ? null : radio.clientRepeat ?? currentRadio.clientRepeat,
    );
    return BackupNodeProfile(
      nodeName: nodeName == current.nodeName ? null : nodeName,
      position: position == current.position ? null : position,
      privacy: merged == before ? null : merged,
      tuning: unavailable.contains(BackupNodeProfilePart.tuning) || mergedRadio == currentRadio
          ? null : mergedRadio,
      txPowerDbm: unavailable.contains(BackupNodeProfilePart.txPower) || txPowerDbm == current.txPowerDbm
          ? null : txPowerDbm,
      pathHashByteWidth: unavailable.contains(BackupNodeProfilePart.pathHashWidth) ||
          pathHashByteWidth == current.pathHashByteWidth ? null : pathHashByteWidth,
      defaultFloodScope: unavailable.contains(BackupNodeProfilePart.defaultFloodScope) ||
          defaultFloodScope == current.defaultFloodScope ? null : defaultFloodScope,
    );
  }
}

class BackupNodeProfilePreview {
  BackupNodeProfilePreview({
    required this.session,
    required this.nodeKey,
    required this.before,
    required this.source,
    required this.manualAddContactFlags,
    Set<BackupNodeProfilePart> unavailable = const {},
  }) : unavailable = Set.unmodifiable(unavailable),
       changes = source.changesFrom(before, unavailable);

  final Object session;
  final String nodeKey;
  final BackupNodeProfile before;
  final BackupNodeProfile source;
  final BackupNodeProfile changes;
  final Set<BackupNodeProfilePart> unavailable;
  final int manualAddContactFlags;
}

enum BackupNodeProfileStatus { completed, destinationChanged, writeUnconfirmed }

typedef BackupNodeProfileResult = ({int confirmed, BackupNodeProfileStatus status});
