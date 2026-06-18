import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/channel_binary_data_helper.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/message_compression.dart';

void main() {
  group('MessageCompressionMetadata', () {
    test('reports the percentage saved by the final payload', () {
      final metadata = MessageCompressionMetadata.fromByteLengths(
        type: MessageCompressionType.mcmp,
        originalBytes: 100,
        compressedBytes: 67,
      );

      expect(metadata.savingsPercent, 33);
      expect(metadata.originalBytes, 100);
      expect(metadata.payloadBytes, 67);
    });

    test('never reports negative savings', () {
      final metadata = MessageCompressionMetadata.fromByteLengths(
        type: MessageCompressionType.cyr2lat,
        originalBytes: 10,
        compressedBytes: 12,
      );

      expect(metadata.savingsPercent, 0);
    });

    test('shared sender bytes reduce the displayed savings percentage', () {
      final bodyOnly = MessageCompressionMetadata.fromByteLengths(
        type: MessageCompressionType.smaz,
        originalBytes: 100,
        compressedBytes: 50,
      );
      final withSender = MessageCompressionMetadata.fromByteLengths(
        type: MessageCompressionType.smaz,
        originalBytes: 120,
        compressedBytes: 70,
      );

      expect(bodyOnly.savingsPercent, 50);
      expect(bodyOnly.originalBytes, 100);
      expect(bodyOnly.payloadBytes, 50);
      expect(withSender.savingsPercent, 42);
    });

    test('detects incoming SMAZ payloads', () {
      final metadata = MessageCompressionMetadata.fromEncodedText(
        encodedText: 's:abcd',
        decodedText: 'a much longer decoded message',
      );

      expect(metadata?.type, MessageCompressionType.smaz);
      expect(metadata?.savingsPercent, greaterThan(0));
    });

    test('detects incoming MCMP payloads', () {
      final metadata = MessageCompressionMetadata.fromEncodedText(
        encodedText: 'mcmp2:abc',
        decodedText: 'a much longer decoded message',
      );

      expect(metadata?.type, MessageCompressionType.mcmp);
      expect(metadata?.savingsPercent, greaterThan(0));
    });
  });

  group('binary MCMP payload weight', () {
    test('always includes data headers and sender envelope', () {
      expect(
        ChannelBinaryDataHelper.uncompressedBinaryPayloadLength('hello', 'Me'),
        11,
      );
      expect(ChannelBinaryDataHelper.finalBinaryPayloadLength(7), 10);
    });
  });

  group('showCompressionRatio setting', () {
    test('is disabled by default', () {
      expect(AppSettings().showCompressionRatio, isFalse);
      expect(AppSettings().compressionRatioWithSenderName, isFalse);
      expect(AppSettings.fromJson(const {}).showCompressionRatio, isFalse);
      expect(
        AppSettings.fromJson(const {}).compressionRatioWithSenderName,
        isFalse,
      );
    });

    test('survives JSON persistence', () {
      final restored = AppSettings.fromJson(
        AppSettings(
          showCompressionRatio: true,
          compressionRatioWithSenderName: true,
        ).toJson(),
      );

      expect(restored.showCompressionRatio, isTrue);
      expect(restored.compressionRatioWithSenderName, isTrue);
    });
  });
}
