import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'windows_notification_identity.dart';

/// How the removal of the legacy notification identity ended.
enum LegacyNotificationCleanup {
  /// No key of the legacy identity exists.
  absent,

  /// The keys were deleted.
  removed,

  /// A running copy of an earlier build still serves the legacy activator;
  /// the keys stay for it, and the next start asks again.
  inUse,

  /// COM gave no answer, or the registry refused the deletion; the keys stay,
  /// and the next start asks again.
  failed,
}

/// The registry entries of the notification identity every build before the
/// data folder used, `org.meshcore.open.app` with its fixed activator GUID.
///
/// An earlier build writes them again at every start and shows its toasts
/// under them, so they go only while no such build is running: a running
/// copy serves the activator's class object through COM, and
/// `CoGetClassObject` for that GUID finds it, from any process, without
/// starting anything, since the plugin registers no `LocalServer32`. With no
/// copy serving it COM answers `REGDB_E_CLASSNOTREG`, and the two keys are
/// deleted. Everything runs on a background isolate: a hung old copy would
/// hold the COM call, and the startup must not wait for it.
abstract final class LegacyNotificationRegistry {
  static const String _appUserModelId =
      WindowsNotificationIdentity.legacyAppUserModelId;

  /// The two keys the notifications plugin writes for an identity, under
  /// `HKEY_CURRENT_USER`.
  static const List<String> keys = [
    'Software\\Classes\\AppUserModelId\\$_appUserModelId',
    'Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications\\Backup\\'
        '$_appUserModelId',
  ];

  static Future<LegacyNotificationCleanup> removeWhenUnused() {
    if (!Platform.isWindows) {
      return Future.value(LegacyNotificationCleanup.absent);
    }
    return Isolate.run(
      () => removeWhenUnusedSync(
        keys: keys,
        activatorGuid: WindowsNotificationIdentity.legacyGuid,
      ),
    );
  }

  /// The work itself, on the calling thread: [keys] under
  /// `HKEY_CURRENT_USER` go when none is missing and no process serves the
  /// class object of [activatorGuid]. The registry is read first, so the
  /// usual start, with nothing left to remove, asks COM nothing.
  @visibleForTesting
  static LegacyNotificationCleanup removeWhenUnusedSync({
    required List<String> keys,
    required String activatorGuid,
  }) {
    final present = keys.where(_keyExists).toList();
    if (present.isEmpty) return LegacyNotificationCleanup.absent;
    switch (_activatorServed(activatorGuid)) {
      case true:
        return LegacyNotificationCleanup.inUse;
      case null:
        return LegacyNotificationCleanup.failed;
      case false:
        break;
    }
    var removed = false;
    for (final key in present) {
      final status = _withUtf16(key, (text) => _regDeleteTree(_hkcu, text));
      if (status == _errorSuccess) {
        removed = true;
      } else if (status != _errorFileNotFound) {
        return LegacyNotificationCleanup.failed;
      }
    }
    return removed
        ? LegacyNotificationCleanup.removed
        : LegacyNotificationCleanup.absent;
  }

  /// The sixteen bytes of [guid] as COM lays a GUID out in memory: the first
  /// three groups little-endian, the last eight bytes as written.
  @visibleForTesting
  static Uint8List guidBytes(String guid) {
    if (guid.length != 36 ||
        guid[8] != '-' ||
        guid[13] != '-' ||
        guid[18] != '-' ||
        guid[23] != '-') {
      throw ArgumentError.value(guid, 'guid', 'not of the form 8-4-4-4-12');
    }
    final hex = guid.replaceAll('-', '');
    int field(int start, int digits) =>
        int.parse(hex.substring(start, start + digits), radix: 16);
    final bytes = Uint8List(16);
    ByteData.sublistView(bytes)
      ..setUint32(0, field(0, 8), Endian.little)
      ..setUint16(4, field(8, 4), Endian.little)
      ..setUint16(6, field(12, 4), Endian.little);
    for (var i = 0; i < 8; i++) {
      bytes[8 + i] = field(16 + 2 * i, 2);
    }
    return bytes;
  }

  /// A key that cannot be opened for a reason other than its absence counts
  /// as present: the deletion then reports what the registry says.
  static bool _keyExists(String key) {
    return _withBuffer(sizeOf<IntPtr>(), (handle) {
      final status = _withUtf16(
        key,
        (text) =>
            _regOpenKeyEx(_hkcu, text, 0, _keyRead, handle.cast<IntPtr>()),
      );
      if (status == _errorSuccess) _regCloseKey(handle.cast<IntPtr>().value);
      return status != _errorFileNotFound;
    });
  }

  /// Whether a process serves the class object of [guid]: true or false when
  /// COM said, null when it could not be asked or answered something else.
  static bool? _activatorServed(String guid) {
    final initialised = _coInitializeEx(nullptr, _coinitMultithreaded);
    // S_OK and S_FALSE are balanced by CoUninitialize; a thread already in
    // the other apartment model (RPC_E_CHANGED_MODE) still makes COM calls.
    final balance = initialised == _sOk || initialised == _sFalse;
    if (!balance && _code(initialised) != _rpcEChangedMode) return null;
    try {
      return _withBuffer(16 + 16 + sizeOf<Pointer<Void>>(), (buffer) {
        final clsid = buffer.cast<Uint8>();
        final iid = clsid + 16;
        final out = (clsid + 32).cast<Pointer<Void>>();
        clsid.asTypedList(16).setAll(0, guidBytes(guid));
        iid.asTypedList(16).setAll(0, guidBytes(_iidIClassFactory));
        out.value = nullptr;
        final hr = _coGetClassObject(
          clsid,
          _clsctxLocalServer,
          nullptr,
          iid,
          out,
        );
        if (hr == _sOk) {
          _release(out.value);
          return true;
        }
        return _code(hr) == _regdbEClassNotReg ? false : null;
      });
    } finally {
      if (balance) _coUninitialize();
    }
  }

  /// `IUnknown::Release`, the third entry of the object's vtable.
  static void _release(Pointer<Void> unknown) {
    if (unknown == nullptr) return;
    final vtable = Pointer<Pointer<IntPtr>>.fromAddress(unknown.address).value;
    final release = Pointer<NativeFunction<Uint32 Function(Pointer<Void>)>>
        .fromAddress(vtable[2])
        .asFunction<int Function(Pointer<Void>)>();
    release(unknown);
  }

  /// An HRESULT or status as the unsigned 32-bit value the headers name.
  static int _code(int value) => value & 0xFFFFFFFF;

  static T _withUtf16<T>(String text, T Function(Pointer<Uint16>) use) {
    final units = text.codeUnits;
    return _withBuffer((units.length + 1) * 2, (buffer) {
      buffer.cast<Uint16>().asTypedList(units.length + 1)
        ..setRange(0, units.length, units)
        ..[units.length] = 0;
      return use(buffer.cast<Uint16>());
    });
  }

  /// Fixed memory from the process heap for one call, zeroed.
  static T _withBuffer<T>(int bytes, T Function(Pointer<Void>) use) {
    final address = _globalAlloc(_gmemFixed | _gmemZeroInit, bytes);
    if (address == 0) throw StateError('GlobalAlloc of $bytes bytes failed');
    try {
      return use(Pointer<Void>.fromAddress(address));
    } finally {
      _globalFree(address);
    }
  }
}

/// `HKEY_CURRENT_USER` as winreg.h defines it, `(ULONG_PTR)((LONG)0x80000001)`:
/// the 32-bit constant sign-extended to the pointer size.
const int _hkcu = -0x7FFFFFFF;
const int _keyRead = 0x20019;
const int _errorSuccess = 0;
const int _errorFileNotFound = 2;
const int _gmemFixed = 0x0000;
const int _gmemZeroInit = 0x0040;
const int _sOk = 0;
const int _sFalse = 1;
const int _coinitMultithreaded = 0;
const int _clsctxLocalServer = 0x4;
const int _rpcEChangedMode = 0x80010106;
const int _regdbEClassNotReg = 0x80040154;
const String _iidIClassFactory = '00000001-0000-0000-c000-000000000046';

// Top-level finals are initialised on first use, so nothing here is looked up
// on a platform that has no such library.
final DynamicLibrary _advapi32 = DynamicLibrary.open('advapi32.dll');
final DynamicLibrary _ole32 = DynamicLibrary.open('ole32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final _regOpenKeyEx = _advapi32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint16>, Uint32, Uint32, Pointer<IntPtr>),
      int Function(int, Pointer<Uint16>, int, int, Pointer<IntPtr>)
    >('RegOpenKeyExW');
final _regCloseKey = _advapi32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');
final _regDeleteTree = _advapi32
    .lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint16>),
      int Function(int, Pointer<Uint16>)
    >('RegDeleteTreeW');
final _coInitializeEx = _ole32
    .lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)
    >('CoInitializeEx');
final _coUninitialize = _ole32
    .lookupFunction<Void Function(), void Function()>('CoUninitialize');
final _coGetClassObject = _ole32
    .lookupFunction<
      Int32 Function(
        Pointer<Uint8>,
        Uint32,
        Pointer<Void>,
        Pointer<Uint8>,
        Pointer<Pointer<Void>>,
      ),
      int Function(
        Pointer<Uint8>,
        int,
        Pointer<Void>,
        Pointer<Uint8>,
        Pointer<Pointer<Void>>,
      )
    >('CoGetClassObject');
final _globalAlloc = _kernel32
    .lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>(
      'GlobalAlloc',
    );
final _globalFree = _kernel32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalFree');
