import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/mcotxt_app_codec.dart';
import 'package:meshcore_open/mcotxt/mcotxt.dart';

void main() {
  group('MCOtxt UTF-8 fallback', () {
    for (final text in <String>[
      'Привет🙂',
      'Hello🙂',
      'Привет 東京',
      '你好世界',
      '🙂👍🔥',
      '❤️',
      '👨‍👩‍👧‍👦',
      'Температура 23°',
      'Подожди… сейчас',
      'Привет MeshCore 🙂 OK',
    ]) {
      test('roundtrips $text', () {
        final encoded = McotxtCodec.encode(text);
        final decoded = McotxtCodec.decode(
          encoded.data,
          bitLength: encoded.bitLength,
        );

        expect(decoded.text, McotxtModelRegistry.normalizeInputText(text));
        expect(encoded.decodedText, decoded.text);
      });
    }

    test('reports UTF8 fallback stats and never skips valid Unicode', () {
      final encoded = McotxtCodec.encode(
        'Hello 🙂👍🔥 world',
        options: const McotxtEncodeOptions(collectStats: true),
      );
      final stats = encoded.stats!;

      expect(encoded.decodedText, 'Hello 🙂👍🔥 world');
      expect(stats.skippedCharacters, 0);
      expect(stats.utf8FallbackRuns, 1);
      expect(stats.utf8FallbackCodepoints, 3);
      expect(stats.utf8FallbackBytes, 12);
      expect(stats.utf8FallbackBits, 14 + 12 * 8);
      expect(
        encoded.debugTokens,
        anyElement(
          allOf(
            startsWith('UTF8_RUN(len=12'),
            contains('text='),
            contains('bytes=F0 9F 99 82 F0 9F 91 8D F0 9F 94 A5'),
          ),
        ),
      );
    });

    test('keeps exactly 32 UTF-8 fallback bytes in one run', () {
      final text = '${List.filled(64, 'hello ').join()}'
          '${List.filled(8, '🙂').join()}'
          '${List.filled(64, ' hello').join()}';
      final encoded = McotxtCodec.encode(
        text,
        options: const McotxtEncodeOptions(collectStats: true),
      );

      expect(encoded.decodedText, text);
      expect(encoded.encodingMode, McotxtEncodingMode.mcotxt);
      expect(encoded.stats!.utf8FallbackRuns, 1);
      expect(encoded.stats!.utf8FallbackBytes, 32);
    });

    test('splits fallback runs above 32 bytes without breaking UTF-8', () {
      final text = '${List.filled(64, 'hello ').join()}'
          '${List.filled(9, '🙂').join()}'
          '${List.filled(64, ' hello').join()}';
      final encoded = McotxtCodec.encode(
        text,
        options: const McotxtEncodeOptions(collectStats: true),
      );

      expect(encoded.decodedText, text);
      expect(encoded.encodingMode, McotxtEncodingMode.mcotxt);
      expect(encoded.stats!.utf8FallbackRuns, 2);
      expect(encoded.stats!.utf8FallbackBytes, 36);
    });

    test('UTF8_RUN resets prediction context to START', () {
      final model = McotxtModelRegistry.modelFor(McotxtLanguageId.ru)!;
      final previousRune = model.symbols.firstWhere((rune) {
        final index = model.symbolIndex(rune)!;
        return model.top4[index].first != model.startTop4.first;
      });

      final writer = _writer(McotxtLanguageId.ru)
        ..languageSymbol(McotxtLanguageId.ru, previousRune)
        ..utf8Run('🙂')
        ..top4(0);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(
        decoded.text,
        '${String.fromCharCode(previousRune)}🙂'
        '${String.fromCharCode(model.startTop4.first)}',
      );
    });

    test('UTF8_RUN preserves active language', () {
      final en = McotxtModelRegistry.modelFor(McotxtLanguageId.en)!;
      final writer = _writer(McotxtLanguageId.ru, b: McotxtLanguageId.en)
        ..toggle()
        ..utf8Run('🙂')
        ..top4(0);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(decoded.text, '🙂${String.fromCharCode(en.startTop4.first)}');
    });

    test('truncated UTF8_RUN is rejected', () {
      final writer = _writer(McotxtLanguageId.en)
        ..writeBits(63, 6)
        ..writeBits(2, 3)
        ..writeBits(3, 5)
        ..writeBits(0xf0, 8);

      expect(
        () => McotxtCodec.decode(writer.toBytes(), bitLength: writer.bitLength),
        throwsA(
          isA<McotxtCodecException>().having(
            (error) => error.code,
            'code',
            McotxtCodecError.unexpectedEnd,
          ),
        ),
      );
    });

    test('invalid UTF8_RUN bytes are rejected', () {
      final writer = _writer(McotxtLanguageId.en)
        ..writeBits(63, 6)
        ..writeBits(2, 3)
        ..writeBits(1, 5)
        ..writeBits(0xc3, 8)
        ..writeBits(0x28, 8);

      expect(
        () => McotxtCodec.decode(writer.toBytes(), bitLength: writer.bitLength),
        throwsA(
          isA<McotxtCodecException>().having(
            (error) => error.code,
            'code',
            McotxtCodecError.invalidUtf8Fallback,
          ),
        ),
      );
    });
  });

  group('MCOtxt RAW_UTF8 mode', () {
    test('selects RAW_UTF8 when whole-message UTF-8 is smaller', () {
      const text = '你好世界🙂';
      final encoded = McotxtCodec.encode(text);

      expect(encoded.encodingMode, McotxtEncodingMode.rawUtf8);
      expect(encoded.decodedText, text);
      expect(encoded.data.length, encoded.selectedBytes);
      expect(encoded.bitLength, encoded.selectedBitLength);
      expect(encoded.data.length, encoded.rawUtf8CandidateBytes);
      expect(encoded.rawUtf8CandidateBytes, lessThan(encoded.mcotxtCandidateBytes));
      expect(encoded.bitLength, 16 + utf8.encode(text).length * 8);
    });

    test('prefers normal MCOtxt when payload bytes and bits tie-break allow it', () {
      final encoded = McotxtCodec.encode('');

      expect(encoded.encodingMode, McotxtEncodingMode.mcotxt);
      expect(encoded.data.length, encoded.rawUtf8CandidateBytes);
      expect(encoded.bitLength, lessThan(encoded.rawUtf8CandidateBitLength));
    });

    test('decodes byte-aligned RAW_UTF8 payload', () {
      const text = 'Привет 東京🙂';
      final writer = _rawUtf8Writer(text);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(decoded.text, text);
      expect(decoded.languageA, isNull);
      expect(decoded.languageB, isNull);
      expect(decoded.usedTables, isEmpty);
    });

    test('rejects non-zero RAW_UTF8 padding bits', () {
      final writer = _McotxtTestWriter()
        ..writeBits(McotxtCodec.version, 3)
        ..writeBits(7, 3)
        ..writeBits(McotxtModelRegistry.rawUtf8HeaderFormat, 3)
        ..writeBits(1, 7);

      expect(
        () => McotxtCodec.decode(writer.toBytes(), bitLength: writer.bitLength),
        throwsA(
          isA<McotxtCodecException>().having(
            (error) => error.code,
            'code',
            McotxtCodecError.invalidRawUtf8,
          ),
        ),
      );
    });

    test('rejects invalid RAW_UTF8 bytes', () {
      final writer = _McotxtTestWriter()
        ..writeBits(McotxtCodec.version, 3)
        ..writeBits(7, 3)
        ..writeBits(McotxtModelRegistry.rawUtf8HeaderFormat, 3)
        ..writeBits(0, 7)
        ..writeBits(0xc3, 8)
        ..writeBits(0x28, 8);

      expect(
        () => McotxtCodec.decode(writer.toBytes(), bitLength: writer.bitLength),
        throwsA(
          isA<McotxtCodecException>().having(
            (error) => error.code,
            'code',
            McotxtCodecError.invalidRawUtf8,
          ),
        ),
      );
    });
  });

  group('MCOtxt app string candidates', () {
    test('uses container UTF-8 for short metadata when it is smaller', () {
      final body = McotxtAppCodec.encodeBody(
        text: 'hello hello hello hello hello',
        timestamp: 1,
        senderName: 'A',
      );
      final decoded = McotxtAppCodec.decodeBody(body);

      expect(decoded.senderName, 'A');
      expect(decoded.text, 'hello hello hello hello hello');
      expect(body[5], 1);
    });

    test('keeps MCOtxt for long compressible message text', () {
      final text = List.filled(80, 'hello ').join();
      final body = McotxtAppCodec.encodeBody(text: text, timestamp: 1);
      final decoded = McotxtAppCodec.decodeBody(body);

      expect(decoded.text, text);
      expect(body[5], 0);
    });

    test('keeps main message text in MCOtxt string mode', () {
      final body = McotxtAppCodec.encodeBody(text: 'A', timestamp: 1);
      final decoded = McotxtAppCodec.decodeBody(body);

      expect(decoded.text, 'A');
      expect(body[5], 0);
    });
  });

  group('MCOtxt extended language header', () {
    test('normal header remains 9 bits for current inline languages', () {
      final encoded = McotxtCodec.encode(
        'Hello',
        options: const McotxtEncodeOptions(languageA: McotxtLanguageId.en),
      );

      expect(encoded.bitStream.substring(0, 9), '001000111');
    });

    test('reserved extended header formats are rejected', () {
      final writer = _McotxtTestWriter()
        ..writeBits(McotxtCodec.version, 3)
        ..writeBits(7, 3)
        ..writeBits(1, 3);

      expect(
        () => McotxtCodec.decode(writer.toBytes(), bitLength: writer.bitLength),
        throwsA(
          isA<McotxtCodecException>().having(
            (error) => error.code,
            'code',
            McotxtCodecError.unsupportedExtendedHeader,
          ),
        ),
      );
    });

    test('SWITCH_OTHER_LANGUAGE uses 8-bit global language IDs', () {
      final en = McotxtModelRegistry.modelFor(McotxtLanguageId.en)!;
      final ru = McotxtModelRegistry.modelFor(McotxtLanguageId.ru)!;
      final writer = _writer(McotxtLanguageId.en)
        ..switchOther(McotxtLanguageId.ru.globalId)
        ..top4(0)
        ..switchOther(McotxtLanguageId.en.globalId)
        ..top4(0);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(
        decoded.text,
        '${String.fromCharCode(ru.startTop4.first)}'
        '${String.fromCharCode(en.startTop4.first)}',
      );
    });

    test('unknown global language IDs are rejected', () {
      final writer = _writer(McotxtLanguageId.en)..switchOther(254);

      expect(
        () => McotxtCodec.decode(writer.toBytes(), bitLength: writer.bitLength),
        throwsA(
          isA<McotxtCodecException>().having(
            (error) => error.code,
            'code',
            McotxtCodecError.invalidOtherLanguage,
          ),
        ),
      );
    });
  });

  group('MCOtxt punctuation prediction context', () {
    test('message start uses startTop4', () {
      final model = McotxtModelRegistry.modelFor(McotxtLanguageId.ru)!;
      expect(model.startTop4.first, isNot(model.punctStartTop4.first));

      final writer = _writer(McotxtLanguageId.ru)..top4(0);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(decoded.text, String.fromCharCode(model.startTop4.first));
    });

    test('ordinary punctuation uses punctStartTop4', () {
      final model = McotxtModelRegistry.modelFor(McotxtLanguageId.ru)!;
      final spaceRank = model.punctStartTop4.indexOf(McotxtPunctuation.space);
      expect(spaceRank, isNonNegative);
      expect(model.startTop4[spaceRank], isNot(McotxtPunctuation.space));

      final writer = _writer(McotxtLanguageId.ru)
        ..punctuation(',')
        ..top4(spaceRank);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(decoded.text, ', ');
    });

    test('symbol after language SPACE uses regular top4 row', () {
      final model = McotxtModelRegistry.modelFor(McotxtLanguageId.ru)!;
      final spaceRank = model.punctStartTop4.indexOf(McotxtPunctuation.space);
      final spaceIndex = model.symbolIndex(McotxtPunctuation.space)!;
      final nextRune = model.top4[spaceIndex].first;

      final writer = _writer(McotxtLanguageId.ru)
        ..punctuation(',')
        ..top4(spaceRank)
        ..top4(0);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(decoded.text, ', ${String.fromCharCode(nextRune)}');
    });

    test('newline resets to startTop4', () {
      final model = McotxtModelRegistry.modelFor(McotxtLanguageId.ru)!;
      expect(model.startTop4.first, isNot(model.punctStartTop4.first));

      final writer = _writer(McotxtLanguageId.ru)
        ..punctuation('\n')
        ..top4(0);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(decoded.text, '\n${String.fromCharCode(model.startTop4.first)}');
    });

    test('language toggle resets to startTop4 of the new language', () {
      final en = McotxtModelRegistry.modelFor(McotxtLanguageId.en)!;
      final writer = _writer(McotxtLanguageId.ru, b: McotxtLanguageId.en)
        ..toggle()
        ..top4(0);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(decoded.text, String.fromCharCode(en.startTop4.first));
    });

    test('reset context returns to startTop4', () {
      final model = McotxtModelRegistry.modelFor(McotxtLanguageId.ru)!;
      final writer = _writer(McotxtLanguageId.ru)
        ..punctuation(',')
        ..resetContext()
        ..top4(0);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      expect(decoded.text, ',${String.fromCharCode(model.startTop4.first)}');
    });

    test('shift after punctuation keeps after-punctuation prediction', () {
      final model = McotxtModelRegistry.modelFor(McotxtLanguageId.en)!;
      final rank = model.punctStartTop4.indexWhere(
        (rune) => model.lowercaseToUppercase.containsKey(rune),
      );
      expect(rank, isNonNegative);
      expect(model.startTop4[rank], isNot(model.punctStartTop4[rank]));

      final writer = _writer(McotxtLanguageId.en)
        ..punctuation('.')
        ..shift()
        ..top4(rank);
      final decoded = McotxtCodec.decode(
        writer.toBytes(),
        bitLength: writer.bitLength,
      );

      final expectedRune =
          model.lowercaseToUppercase[model.punctStartTop4[rank]]!;
      expect(decoded.text, '.${String.fromCharCode(expectedRune)}');
    });

    test('encoder and decoder roundtrip with punctuation contexts', () {
      for (final text in <String>[
        'Привет, как дела',
        'Привет\nКак дела',
        'Привет MeshCore!',
        '. Hello',
      ]) {
        final encoded = McotxtCodec.encode(text);
        final decoded = McotxtCodec.decode(
          encoded.data,
          bitLength: encoded.bitLength,
        );

        expect(decoded.text, encoded.decodedText);
      }
    });
  });
}

_McotxtTestWriter _writer(McotxtLanguageId a, {McotxtLanguageId? b}) {
  return _McotxtTestWriter()
    ..writeBits(McotxtCodec.version, 3)
    ..writeBits(a.wireId, 3)
    ..writeBits(b?.wireId ?? McotxtModelRegistry.languageNoneWireId, 3);
}

_McotxtTestWriter _rawUtf8Writer(String text) {
  final writer = _McotxtTestWriter()
    ..writeBits(McotxtCodec.version, 3)
    ..writeBits(7, 3)
    ..writeBits(McotxtModelRegistry.rawUtf8HeaderFormat, 3)
    ..writeBits(0, 7);
  for (final byte in utf8.encode(text)) {
    writer.writeBits(byte, 8);
  }
  return writer;
}

class _McotxtTestWriter extends BitWriter {
  void top4(int rank) {
    writeBit(0);
    writeBits(rank, 2);
  }

  void punctuation(String value) {
    final runes = value.runes.toList(growable: false);
    expect(runes, hasLength(1));
    final id = McotxtPunctuation.idByRune[runes.single];
    expect(id, isNotNull);
    writeBits(6, 3);
    writeBits(id!, 5);
  }

  void languageSymbol(McotxtLanguageId language, int rune) {
    final model = McotxtModelRegistry.modelFor(language)!;
    final primaryId = model.primaryId(rune);
    if (primaryId != null) {
      writeBits(2, 2);
      writeBits(primaryId, 5);
      return;
    }
    final extensionId = model.extensionId(rune);
    expect(extensionId, isNotNull);
    writeBits(14, 4);
    writeBits(extensionId!, 5);
  }

  void shift() {
    writeBits(30, 5);
  }

  void toggle() {
    writeBits(62, 6);
  }

  void resetContext() {
    writeBits(63, 6);
    writeBits(1, 3);
  }

  void switchOther(int globalLanguageId) {
    writeBits(63, 6);
    writeBits(0, 3);
    writeBits(globalLanguageId, 8);
  }

  void utf8Run(String value) {
    final utf8Bytes = utf8.encode(value);
    expect(utf8Bytes.length, inInclusiveRange(1, 32));
    writeBits(63, 6);
    writeBits(2, 3);
    writeBits(utf8Bytes.length - 1, 5);
    for (final byte in utf8Bytes) {
      writeBits(byte, 8);
    }
  }
}
