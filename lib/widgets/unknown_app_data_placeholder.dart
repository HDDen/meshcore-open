import '../helpers/channel_binary_data_helper.dart';
import '../l10n/app_localizations.dart';

/// What the screens show in place of a channel data packet this build could
/// not read (see [ChannelBinaryDataHelper.tryDescribeUnknownAppData]). The
/// stored message text is the sentinel [UnknownChannelAppData.sentinelText];
/// every place that would print it asks here instead, so the wording lives
/// once and follows the UI language rather than the language the message was
/// received under. The namespace is named in every form; subtype and version
/// only when the envelope was ours to read.
String unknownAppDataPlaceholderText(
  AppLocalizations l10n,
  UnknownChannelAppData data,
) {
  final subtypeId = data.subtypeId;
  final version = data.version;
  if (subtypeId == null || version == null) {
    return l10n.chat_unknownAppDataPlaceholderNamespace(data.namespaceLabel);
  }
  return l10n.chat_unknownAppDataPlaceholder(
    data.namespaceLabel,
    subtypeId,
    version,
  );
}
