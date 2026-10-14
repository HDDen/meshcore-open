import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meshcore_open/helpers/qr_gallery_scan.dart';

// The gallery scan behind the QR scanners: the picker and the picture reader
// are stubbed, and the outcome is read off the codes the picture holds and
// the kind the caller accepts.

bool _isChannel(String value) => value.startsWith('meshcore://channel/');

// On a desktop or a phone the name comes from the path; `name` is for the web.
Future<XFile?> _picked() async => XFile.fromData(Uint8List(0), path: 'qr.png');

void main() {
  test('a closed picker is a cancellation and reads nothing', () async {
    var reads = 0;
    final scan = await scanQrFromGallery(
      accepts: _isChannel,
      pickPicture: () async => null,
      readPicture: (_) async {
        reads++;
        return ['meshcore://channel/add?name=a&secret=00'];
      },
    );
    expect(scan.status, QrGalleryScanStatus.cancelled);
    expect(scan.value, isNull);
    expect(reads, 0);
  });

  test('a picker that cannot open is reported as such', () async {
    final scan = await scanQrFromGallery(
      accepts: _isChannel,
      pickPicture: () async => throw StateError('no gallery'),
      readPicture: (_) async => const [],
    );
    expect(scan.status, QrGalleryScanStatus.pickerFailed);
  });

  test('a picture without a code, or one that cannot be read', () async {
    final empty = await scanQrFromGallery(
      accepts: _isChannel,
      pickPicture: _picked,
      readPicture: (_) async => const [],
    );
    expect(empty.status, QrGalleryScanStatus.noBarcode);

    final unreadable = await scanQrFromGallery(
      accepts: _isChannel,
      pickPicture: _picked,
      readPicture: (_) async => throw UnsupportedError('no reader'),
    );
    expect(unreadable.status, QrGalleryScanStatus.noBarcode);
  });

  test('codes of another kind are no match', () async {
    final scan = await scanQrFromGallery(
      accepts: _isChannel,
      pickPicture: _picked,
      readPicture: (_) async => ['meshcore://contact/add?public_key=00'],
    );
    expect(scan.status, QrGalleryScanStatus.noMatch);
    expect(scan.value, isNull);
  });

  test('the first accepted code is the answer', () async {
    final scan = await scanQrFromGallery(
      accepts: _isChannel,
      pickPicture: _picked,
      readPicture: (picture) async {
        expect(picture.path, 'qr.png');
        return [
          'https://example.org',
          'meshcore://channel/add?name=a&secret=00',
          'meshcore://channel/add?name=b&secret=11',
        ];
      },
    );
    expect(scan.status, QrGalleryScanStatus.found);
    expect(scan.value, 'meshcore://channel/add?name=a&secret=00');
  });
}
