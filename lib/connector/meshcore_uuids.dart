class MeshCoreUuids {
  static const String service = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String rxCharacteristic = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  static const String txCharacteristic = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  /// Known advertised-name prefixes used by stock MeshCore firmware builds.
  /// Discovery no longer filters on these (it filters on the [service] UUID so
  /// that community forks with custom names are still found); kept for
  /// reference and possible future display heuristics.
  static const List<String> deviceNamePrefixes = [
    "MeshCore-",
    "Whisper-",
    "WisCore-",
    "Seeed",
    "Lilygo",
    "HT-",
    "LowMesh_MC_",
    "NRF52",
  ];
}
