import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../helpers/saved_path_trace_result.dart';
import 'contact.dart';

/// The map's path-trace builder state: the hops picked so far, the trace
/// mode and the last result. Held by `UiViewStateService` for the app session
/// so leaving the map or opening the result doesn't discard it.
class MapPathTraceDraft {
  bool active = false;
  Uint8List? radioKey;
  final List<int> pathBytes = [];
  final List<int> hopWidths = [];
  final List<Contact> contacts = [];
  final List<LatLng> points = [];
  bool returnPath = true;
  int hashByteWidth = 1;
  LatLng? start;
  final Map<String, LatLng> positionOverrides = {};
  String? editorText;
  SavedPathTraceResult? lastResult;
  List<Contact> resultContacts = const [];
  int _revision = 0;

  int get revision => _revision;

  // Keep the upstream convenience API; the map stores the richer snapshot
  // so replay also preserves the fork's direct-echo observations.
  Uint8List? get lastResultFrame => lastResult?.frame;
  set lastResultFrame(Uint8List? value) {
    lastResult = value == null ? null : SavedPathTraceResult(frame: value);
  }

  bool get hasHops => pathBytes.isNotEmpty;

  bool belongsTo(Uint8List? selfKey) => radioKey == null
      ? !hasHops
      : selfKey != null && listEquals(radioKey, selfKey);

  void invalidateResult() {
    _revision++;
    lastResult = null;
    resultContacts = const [];
  }

  void clear() {
    pathBytes.clear();
    hopWidths.clear();
    contacts.clear();
    points.clear();
    start = null;
    positionOverrides.clear();
    editorText = null;
    invalidateResult();
  }
}
