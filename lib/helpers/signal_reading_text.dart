import 'package:flutter/material.dart';

import '../widgets/signal_ui.dart';
import '../widgets/snr_indicator.dart';

/// Colour for a LoRa RSSI reading in dBm, on the scale
/// [signalUiForStrengthTier] already paints for SNR.
///
/// The steps sit far below the BLE ones in `widgets/device_tile.dart`: LoRa
/// still carries at levels where Bluetooth has long since given up.
Color loraRssiColor(num rssiDbm) => signalUiForStrengthTier(
  rssiDbm >= -90
      ? 0
      : rssiDbm >= -105
      ? 1
      : rssiDbm >= -115
      ? 2
      : rssiDbm >= -125
      ? 3
      : 4,
).color;

/// What our own radio made of the reception a message arrived on — the last
/// hop of its path, or the sender itself when nobody relayed it — as a tail
/// for the hop list of a channel bubble.
///
/// Spans rather than a widget, so the caller appends them to the hop list's
/// own `Text` instead of adding another chip to the meta row's `Wrap`: that
/// way they read as the tail of the list and inherit its font, and only the
/// colour sets them apart — on the five-step scale the SNR indicator in the
/// app bar paints, with [spreadingFactor] deciding what counts as a good SNR.
///
/// Each reading is glued to what stands before it with a non-breaking space:
/// they describe the hop the list ends with, and a plain space would let the
/// line break strand them on a line of their own. The list itself still breaks
/// freely — its separator is a comma plus a zero-width space — so a long path
/// wrapping carries the last hop and its signal over together. With nothing in
/// front of them ([afterHopList] false, a directly heard message) the first
/// reading opens the run and takes no glue, or it would sit a space further
/// from the route chip than every other row does.
///
/// Empty when neither reading is known, which is every message stored before
/// they were recorded. RSSI alone is missing whenever the message arrived as a
/// channel-message response rather than through the raw RX log, the only frame
/// that reports it.
List<InlineSpan> signalReadingSpans({
  required double? snr,
  required int? rssi,
  required int? spreadingFactor,
  required bool afterHopList,
}) {
  final spans = <InlineSpan>[];
  String glue() => spans.isEmpty && !afterHopList ? '' : '\u00A0';
  if (snr != null) {
    spans.add(
      TextSpan(
        text: '${glue()}${snr.toStringAsFixed(1)}dB',
        style: TextStyle(color: snrUiFromSNR(snr, spreadingFactor).color),
      ),
    );
  }
  if (rssi != null) {
    spans.add(
      TextSpan(
        text: '${glue()}${rssi}dBm',
        style: TextStyle(color: loraRssiColor(rssi)),
      ),
    );
  }
  return spans;
}
