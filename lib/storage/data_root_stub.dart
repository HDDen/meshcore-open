import 'data_root_core.dart';

/// The web build keeps the browser's storage and has no data folder.
Future<DataRootOutcome> prepareDataRoot(List<String> args) async {
  DataRoot.launchArguments = List.unmodifiable(args);
  return const DataRootReady();
}

Future<void> releaseDataRootLock() async {}
