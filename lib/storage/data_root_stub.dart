import 'data_root_core.dart';

/// The web build keeps the browser's storage and has no data folder.
Future<DataRootOutcome> prepareDataRoot(List<String> args) async {
  DataRoot.launchArguments = List.unmodifiable(args);
  return const DataRootReady();
}

Future<void> releaseDataRootLock() async {}

/// No data folder, so nothing to copy into one.
Future<DataTransferOffer?> findDataTransferOffer({
  LegacyDataLocations? legacy,
}) async => null;

Future<int> measureDataTransfer(DataTransferOffer offer) async => 0;

Future<void> transferData(
  DataTransferOffer offer, {
  void Function(int copied, int total)? onProgress,
}) => throw UnsupportedError('The web build has no data folder.');

Future<DataCleanupOffer?> findDataCleanupOffer() async => null;

Future<int> measureDataCleanup(DataCleanupOffer offer) async => 0;

Future<List<String>> deleteOldData(DataCleanupOffer offer) async => const [];

Future<void> declineDataCleanup(DataCleanupOffer offer) async {}
