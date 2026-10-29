import 'dart:typed_data';

import '../models/image_codec_support.dart';
import '../services/image_chunk_transport.dart';
import '../services/received_image_store.dart';

/// One saved image, regardless of its number of transport chunks.
class ChannelImageReplay {
  const ChannelImageReplay({
    required this.messageId,
    required this.receivedAt,
    required this.frames,
  });

  final String messageId;
  final DateTime receivedAt;
  final List<Uint8List> frames;
}

/// Files may have been evicted since the index was read. A missing image does
/// not prevent the remaining images (or ordinary text) from being replayed.
Future<List<ChannelImageReplay>> loadSavedChannelImageReplay({
  required Iterable<ReceivedImageEntry> images,
  required Future<Uint8List?> Function(String) readBitstream,
  required int channelIndex,
}) async {
  final result = <ChannelImageReplay>[];
  for (final image in images) {
    if (!image.bitstreamStored || image.isOutgoing || image.metadataAssumed) {
      continue;
    }
    try {
      final bytes = await readBitstream(image.streamId);
      if (bytes == null) continue;
      result.add(buildChannelImageReplay(image, bytes, channelIndex));
    } catch (_) {
      // File eviction, truncated bytes or an unsupported stored format.
    }
  }
  return result;
}

/// Reuses the wire builder; neither the neural decoder nor PNG is required.
/// Radio path and SNR were not retained by the image store, so replay uses
/// unknown path/zero SNR rather than inventing reception measurements.
ChannelImageReplay buildChannelImageReplay(
  ReceivedImageEntry image,
  Uint8List bitstream,
  int channelIndex,
) {
  if (bitstream.isEmpty || bitstream.length != image.bitstreamByteCount ||
      image.rate != kShippingAeicRatePoint) {
    throw ArgumentError('Missing or truncated saved AEIC bitstream');
  }
  final chunks = buildImageChunks(
    payload: bitstream,
    metadata: ImageStreamMetadata(
      rate: uiRatePointForAeic(image.rate),
      squareSize: image.resolution,
      aspectCode: image.aspectCode,
    ),
    senderPrefix: image.senderPrefix,
    imgId: image.imgId,
  );
  return ChannelImageReplay(
    messageId: 'aeic:${image.streamId}',
    receivedAt: image.firstSeen,
    frames: [
      for (final blob in chunks.blobs)
        Uint8List.fromList([
          respCodeChannelDataRecv, 0, 0, 0, channelIndex, 0xff,
          dataTypeAeicImage & 0xff, dataTypeAeicImage >> 8,
          blob.length, ...blob,
        ]),
    ],
  );
}
