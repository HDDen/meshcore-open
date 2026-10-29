import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_image_replay.dart';
import 'package:meshcore_open/services/image_chunk_transport.dart';
import 'package:meshcore_open/services/received_image_store.dart';
import 'package:meshcore_open/widgets/image_send_codec_binding.dart';

ReceivedImageEntry _image(String id, int size, {
  bool outgoing = false,
  bool assumed = false,
  bool stored = true,
}) => ReceivedImageEntry(
  streamId: id,
  senderPrefix: 0x1234,
  imgId: 7,
  channelIndex: 1,
  firstSeen: DateTime.utc(2026, 10, 29),
  state: ReceivedImageState.decoderUnavailable,
  receivedChunks: imageDataChunkCount(size),
  totalChunks: imageDataChunkCount(size),
  metadataAssumed: assumed,
  isOutgoing: outgoing,
  bitstreamStored: stored,
  bitstreamByteCount: size,
  aspectCode: 3,
);

void main() {
  for (final size in [1, 156, 209, 409, kImageMaxPayloadBytes]) {
    test('saved AEIC $size bytes reassembles unchanged on the current slot', () {
      final bytes = Uint8List.fromList(List.generate(size, (i) => i & 255));
      final image = _image('12340700000001', size);
      final replay = buildChannelImageReplay(image, bytes, 5);
      final expected = buildImageChunks(
        payload: bytes,
        metadata: const ImageStreamMetadata(
          rate: ImageCodecRatePoint.standard,
          aspectCode: 3,
        ),
        senderPrefix: image.senderPrefix,
        imgId: image.imgId,
      );
      expect(replay.messageId, 'aeic:${image.streamId}');
      expect(replay.receivedAt, image.firstSeen);
      expect(replay.frames.map((f) => f.sublist(9)), expected.blobs);
      final receiver = ImageReassembler();
      ImageReassemblyResult? result;
      for (final frame in replay.frames) {
        expect(frame.sublist(0, 9), [27, 0, 0, 0, 5, 255, 28, 174, frame.length - 9]);
        expect(frame.length, lessThanOrEqualTo(176));
        result ??= receiver.addChunk(
          Uint8List.sublistView(frame, 9), channelIndex: 5,
        ).result;
      }
      expect(result, isNotNull);
      expect(result!.data, bytes);
      expect(result.metadata!.aspectCode, 3);
    });
  }

  test('unavailable bytes and unsupported entries do not hide the next image', () async {
    final reads = <String>[];
    final images = [
      _image('outgoing', 3, outgoing: true),
      _image('incomplete', 3, stored: false),
      _image('unknownMetadata', 3, assumed: true),
      _image('missing', 3),
      _image('truncated', 3),
      _image('ioError', 3),
      _image('good', 3),
    ];
    final result = await loadSavedChannelImageReplay(
      images: images,
      channelIndex: 2,
      readBitstream: (id) async {
        reads.add(id);
        if (id == 'missing') return null;
        if (id == 'ioError') throw StateError('Synthetic eviction');
        return Uint8List(id == 'truncated' ? 2 : 3);
      },
    );
    expect(reads, ['missing', 'truncated', 'ioError', 'good']);
    expect(result.map((image) => image.messageId), ['aeic:good']);
  });
}
