import 'dart:typed_data';

import '../models/channel_message.dart';
import 'channel_resend_coverage.dart';

/// Недостаточное позднее эхо не превращает завершённую серию в успешную.
({int hops, int required})? channelResendShortfallAfterEcho(
  ChannelMessage message,
  ({int hops, int required}) previous, {
  required bool countDistinctRepeaters,
  required int minRepeaters,
  Uint8List? selfPublicKey,
}) {
  if (channelResendSatisfied(
    message,
    minHops: previous.required,
    countDistinctRepeaters: countDistinctRepeaters,
    minRepeaters: minRepeaters,
    selfPublicKey: selfPublicKey,
  )) {
    return null;
  }
  return (hops: message.pathLength ?? 0, required: previous.required);
}

/// Обычному warning достаточно одного эхо; shortfall требует покрытия.
bool channelNeedsRetransmissionWarning(
  ChannelMessage message, {
  required bool hasCoverageShortfall,
}) => message.isOutgoing &&
    message.sentByRadioAt != null &&
    message.status != ChannelMessageStatus.failed &&
    (message.repeatCount == 0 || hasCoverageShortfall);
