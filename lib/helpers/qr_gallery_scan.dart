import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/platform_info.dart';
import 'qr_picture_decoder.dart';

/// What a scan of a picture from the gallery came to.
enum QrGalleryScanStatus {
  /// The picker was closed without a picture.
  cancelled,

  /// The picker could not be opened.
  pickerFailed,

  /// The picture holds no QR code that could be read.
  noBarcode,

  /// The picture holds QR codes, none of them of the kind asked for.
  noMatch,

  /// [QrGalleryScan.value] is the first QR code of the kind asked for.
  found,
}

class QrGalleryScan {
  const QrGalleryScan(this.status, [this.value]);

  final QrGalleryScanStatus status;
  final String? value;
}

typedef QrPicturePicker = Future<XFile?> Function();
typedef QrPictureReader = Future<List<String>> Function(XFile picture);

/// Picks a picture from the gallery (a file dialog on a desktop) and reads
/// the QR codes in it: [accepts] says which code the caller is after, and
/// the first one it accepts is the answer. mobile_scanner reads the picture
/// where it has an implementation for that, Android, iOS and macOS;
/// elsewhere, and whenever it read nothing, zxing2 reads it in pure Dart
/// (see `qr_picture_decoder.dart`), so a code in a downloaded picture scans
/// on Windows and Linux as well, where the camera does not. [pickPicture]
/// and [readPicture] are for tests.
Future<QrGalleryScan> scanQrFromGallery({
  required bool Function(String value) accepts,
  QrPicturePicker pickPicture = _pickFromGallery,
  QrPictureReader readPicture = _readBarcodes,
}) async {
  final XFile? picture;
  try {
    picture = await pickPicture();
  } catch (_) {
    return const QrGalleryScan(QrGalleryScanStatus.pickerFailed);
  }
  if (picture == null) {
    return const QrGalleryScan(QrGalleryScanStatus.cancelled);
  }

  List<String> values;
  try {
    values = await readPicture(picture);
  } catch (_) {
    values = const [];
  }
  if (values.isEmpty) return const QrGalleryScan(QrGalleryScanStatus.noBarcode);
  for (final value in values) {
    if (accepts(value)) return QrGalleryScan(QrGalleryScanStatus.found, value);
  }
  return const QrGalleryScan(QrGalleryScanStatus.noMatch);
}

Future<XFile?> _pickFromGallery() =>
    ImagePicker().pickImage(source: ImageSource.gallery);

Future<List<String>> _readBarcodes(XFile picture) async {
  if (PlatformInfo.isAndroid || PlatformInfo.isIOS || PlatformInfo.isMacOS) {
    final native = await _readWithScanner(picture.path);
    if (native.isNotEmpty) return native;
  }
  final text = await decodeQrPicture(await picture.readAsBytes());
  return text == null ? const [] : [text];
}

Future<List<String>> _readWithScanner(String path) async {
  final controller = MobileScannerController();
  try {
    final capture = await controller.analyzeImage(path);
    final values = <String>[];
    for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) values.add(value);
    }
    return values;
  } catch (_) {
    return const [];
  } finally {
    controller.dispose();
  }
}
