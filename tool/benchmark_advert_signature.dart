import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meshcore_open/helpers/advert_signature.dart';

const _signatureOffset = 36;
const _sampleCount = 32;
const _copies = 8;

Future<void> main() async {
  final ed25519 = Ed25519();
  final keyPair = await ed25519.newKeyPairFromSeed(List.filled(32, 0x29));
  final key = await keyPair.extractPublicKey();
  final corpus = <Uint8List>[];
  final expected = <bool>[];

  for (var i = 0; i < _sampleCount; i++) {
    final timestamp = ByteData(4)..setUint32(0, 1700000000 + i, Endian.little);
    final appData = Uint8List.fromList([0x82, ...'Node ${i + 1}'.codeUnits, 0]);
    final signedHeader = [...key.bytes, ...timestamp.buffer.asUint8List()];
    final signature = await ed25519.sign(
      [...signedHeader, ...appData],
      keyPair: keyPair,
    );
    final frame = Uint8List.fromList([
      ...signedHeader,
      ...signature.bytes,
      ...appData,
    ]);
    final valid = i % 8 != 0;
    if (!valid) frame[advertAppDataOffset + 1] ^= 1;
    corpus.add(frame);
    expected.add(valid);
  }

  Future<bool> uncached(Uint8List frame) => ed25519.verify(
    [
      ...frame.sublist(0, _signatureOffset),
      ...frame.sublist(advertAppDataOffset),
    ],
    signature: Signature(
      frame.sublist(_signatureOffset, advertAppDataOffset),
      publicKey: SimplePublicKey(
        frame.sublist(0, 32),
        type: KeyPairType.ed25519,
      ),
    ),
  );

  Future<void> measure(
    String label,
    Future<bool> Function(Uint8List) verify,
  ) async {
    final timer = Stopwatch()..start();
    var coldUs = 0;
    for (var copy = 0; copy < _copies; copy++) {
      for (var i = 0; i < corpus.length; i++) {
        if (await verify(corpus[i]) != expected[i]) {
          throw StateError('Unexpected signature verdict for frame $i');
        }
      }
      if (copy == 0) coldUs = timer.elapsedMicroseconds;
    }
    timer.stop();
    stdout.writeln(
      '$label coldUs=$coldUs repeatsUs=${timer.elapsedMicroseconds - coldUs}',
    );
  }

  // Warm up the numerical core without populating the signature cache.
  for (final frame in corpus) {
    await uncached(frame);
  }
  stdout.writeln(
    'Synthetic corpus: $_sampleCount envelopes x $_copies; all verdicts checked.',
  );
  stdout.writeln('Ed25519 only. No radio, database, UI or energy measurement.');
  await measure('uncached', uncached);
  await measure('bounded cache', verifyAdvertSignature);
}
