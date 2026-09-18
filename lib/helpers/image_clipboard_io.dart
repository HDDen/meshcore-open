import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A picture on the system clipboard, on the platform where plain system calls
/// can put one there — Windows. See `image_clipboard.dart` for why only that.
class ImageClipboard {
  static bool get isSupported => Platform.isWindows;

  /// Offers the picture in the two forms Windows applications look for: the
  /// registered `PNG` format, which is exact, and `CF_DIB`, which everything
  /// reads and from which the system derives `CF_BITMAP` and `CF_DIBV5` by
  /// itself. [rgba] is [width] x [height] opaque pixels, four bytes each, rows
  /// from the top; [png] is the same picture encoded.
  ///
  /// False when the clipboard stayed busy or refused the data.
  static Future<bool> write({
    required int width,
    required int height,
    required Uint8List rgba,
    required Uint8List png,
  }) async {
    if (!Platform.isWindows) return false;
    final dib = windowsDib(width, height, rgba);
    // Clipboard viewers open the clipboard after every change, so finding it
    // busy for a moment is normal.
    for (var attempt = 0; attempt < 10; attempt++) {
      final written = _writeOnce(png, dib);
      if (written != null) return written;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    return false;
  }

  /// A device-independent bitmap as the clipboard wants it: a
  /// `BITMAPINFOHEADER`, then 32-bit BGRA rows from the bottom one up. The
  /// fourth byte is written as 0xFF whatever the source says, because readers
  /// disagree on what it means in a `BI_RGB` bitmap and a zero there turns the
  /// picture invisible in those that take it for alpha.
  @visibleForTesting
  static Uint8List windowsDib(int width, int height, Uint8List rgba) {
    const headerSize = 40;
    final stride = width * 4;
    if (rgba.length != stride * height) {
      throw ArgumentError('rgba is not $width x $height pixels');
    }
    final dib = Uint8List(headerSize + stride * height);
    ByteData.sublistView(dib, 0, headerSize)
      ..setUint32(0, headerSize, Endian.little) // biSize
      ..setInt32(4, width, Endian.little) // biWidth
      ..setInt32(8, height, Endian.little) // biHeight, positive: bottom-up
      ..setUint16(12, 1, Endian.little) // biPlanes
      ..setUint16(14, 32, Endian.little) // biBitCount
      // biCompression stays 0, BI_RGB, like everything after biSizeImage.
      ..setUint32(20, stride * height, Endian.little); // biSizeImage
    for (var y = 0; y < height; y++) {
      var source = (height - 1 - y) * stride;
      var target = headerSize + y * stride;
      for (var x = 0; x < width; x++) {
        dib[target] = rgba[source + 2];
        dib[target + 1] = rgba[source + 1];
        dib[target + 2] = rgba[source];
        dib[target + 3] = 0xFF;
        source += 4;
        target += 4;
      }
    }
    return dib;
  }

  /// Open, fill and close in one synchronous run: an open clipboard belongs to
  /// the thread that opened it and is closed to every other application, so
  /// nothing may be awaited in between. Null when it could not be opened.
  static bool? _writeOnce(Uint8List png, Uint8List dib) {
    // No owner window. That only rules out delayed rendering, and the data
    // here is handed over whole.
    if (_openClipboard(0) == 0) return null;
    try {
      if (_emptyClipboard() == 0) return false;
      // Formats are offered in the order they were placed, the best one first.
      final pngFormat = _registerFormat('PNG');
      if (pngFormat != 0) _place(pngFormat, png);
      return _place(_cfDib, dib);
    } finally {
      _closeClipboard();
    }
  }

  static bool _place(int format, Uint8List bytes) {
    final handle = _globalAlloc(_gmemMoveable, bytes.length);
    if (handle == 0) return false;
    final memory = _globalLock(handle);
    if (memory == nullptr) {
      _globalFree(handle);
      return false;
    }
    memory.asTypedList(bytes.length).setRange(0, bytes.length, bytes);
    _globalUnlock(handle);
    // The clipboard owns the memory once it has taken it, and only then.
    if (_setClipboardData(format, handle) == 0) {
      _globalFree(handle);
      return false;
    }
    return true;
  }

  /// Zero when the name could not be registered.
  static int _registerFormat(String name) {
    final units = name.codeUnits;
    // Fixed memory: the handle is the address itself.
    final address = _globalAlloc(_gmemFixed, (units.length + 1) * 2);
    if (address == 0) return 0;
    final text = Pointer<Uint16>.fromAddress(address);
    text.asTypedList(units.length + 1)
      ..setRange(0, units.length, units)
      ..[units.length] = 0;
    final format = _registerClipboardFormat(text);
    _globalFree(address);
    return format;
  }
}

const int _cfDib = 8;
const int _gmemFixed = 0x0000;
const int _gmemMoveable = 0x0002;

// Top-level finals are initialised on first use, so nothing here is looked up
// on a platform that has no such library.
final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final _openClipboard = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('OpenClipboard');
final _emptyClipboard = _user32
    .lookupFunction<Int32 Function(), int Function()>('EmptyClipboard');
final _closeClipboard = _user32
    .lookupFunction<Int32 Function(), int Function()>('CloseClipboard');
final _setClipboardData = _user32
    .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
      'SetClipboardData',
    );
final _registerClipboardFormat = _user32
    .lookupFunction<
      Uint32 Function(Pointer<Uint16>),
      int Function(Pointer<Uint16>)
    >('RegisterClipboardFormatW');
final _globalAlloc = _kernel32
    .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
      'GlobalAlloc',
    );
final _globalLock = _kernel32
    .lookupFunction<
      Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)
    >('GlobalLock');
final _globalUnlock = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('GlobalUnlock');
final _globalFree = _kernel32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalFree');
