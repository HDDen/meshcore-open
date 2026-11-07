import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:koni_jxl_flutter/koni_jxl_flutter.dart';

import '../helpers/theme_image_codec.dart';
import '../helpers/theme_media.dart';
import '../models/channel.dart';
import '../models/chat_background.dart';
import '../models/contact.dart';
import '../models/custom_theme.dart';
import '../storage/prefs_manager.dart';
import '../theme/theme_icons.dart';
import '../utils/app_logger.dart';
import 'app_settings_service.dart';
import 'chat_background_image_store.dart';

/// Resolves local and theme backgrounds by chat identity. Picture IO starts
/// when a visible background requests bytes or the user changes a picture.
class ChatBackgroundService extends ChangeNotifier {
  static const _prefsKey = 'chat_backgrounds_v1';
  static const int maxImageSide = 1080;
  static const double jxlDistance = 2.0;
  static const _maxCachedImages = 4;
  static const _maxMissingIds = 32;

  final AppSettingsService _settings;
  final ChatBackgroundImageStore _images;
  final Future<Uint8List?> Function(Uint8List) _encodeImage;
  final Map<String, ChatBackground> _byChat = {};
  final Map<String, Uint8List> _imageCache = {};
  final Set<String> _missing = {};
  final Set<String> _loading = {};
  final Set<String> _draftImages = {};
  Future<void> _storeQueue = Future<void>.value();
  CustomTheme? _activeTheme;
  bool _disposed = false;

  ChatBackgroundService(
    this._settings, {
    ChatBackgroundImageStore? imageStore,
    Future<Uint8List?> Function(Uint8List)? encodeImage,
  }) : _images = imageStore ?? createChatBackgroundImageStore(),
       _encodeImage = encodeImage ?? encodeChatBackgroundJxl {
    _activeTheme = _settings.activeCustomTheme;
    _load();
    _settings.addListener(_settingsChanged);
  }

  static String channelKey(Channel channel) {
    // Unkeyed/offline placeholder slots are not a stable chat identity.
    final id = channel.storageId;
    return id == null || id.isEmpty ? '' : 'channel:$id';
  }

  static String contactKey(Contact contact) => 'contact:${contact.publicKeyHex}';

  void _load() {
    final raw = PrefsManager.instance.getString(_prefsKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      for (final entry in json.entries) {
        final value = ChatBackground.fromJson(entry.value);
        if (value != null) _byChat[entry.key] = value;
      }
    } on FormatException {
      appLogger.warn('Could not read saved chat backgrounds');
    }
  }

  void _settingsChanged() {
    if (_draftImages.isNotEmpty) _draftImages.removeWhere(_isInUse);
    final theme = _settings.activeCustomTheme;
    if (theme == _activeTheme) return;
    _activeTheme = theme;
    if (!_disposed) notifyListeners();
  }

  ChatBackground? chatBackground(String key) => _byChat[key];

  CustomTheme? get overridingTheme {
    final theme = _activeTheme;
    return theme != null && theme.chatBackgroundEverywhere && theme.chatBackground != null
        ? theme
        : null;
  }

  ChatBackground? resolve(String key) =>
      overridingTheme?.chatBackground ?? _byChat[key] ?? _activeTheme?.chatBackground;

  Future<T> _serializeStore<T>(Future<T> Function() action) {
    final result = _storeQueue.then((_) => action());
    _storeQueue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> setChatBackground(String key, ChatBackground? value) async {
    if (key.isEmpty) throw ArgumentError('Chat has no stable background key');
    if (value != null &&
        (value.inlineImage != null ||
            !value.fade.isFinite ||
            value.fade < ChatBackground.minFade ||
            value.fade > ChatBackground.maxFade ||
            (value.imageId != null && !isStoredThemeImageId(value.imageId)) ||
            (value.asset != null && !isThemeAssetPath(value.asset)))) {
      throw ArgumentError('Invalid chat background');
    }
    await _serializeStore(() async {
      if (_byChat[key] == value) return;
      final next = Map<String, ChatBackground>.of(_byChat);
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
      final saved = await PrefsManager.instance.setString(
        _prefsKey,
        jsonEncode(next.map((key, value) => MapEntry(key, value.toJson()))),
      );
      if (!saved) throw StateError('Could not save chat background');
      _byChat
        ..clear()
        ..addAll(next);
      _draftImages.remove(value?.imageId);
      if (!_disposed) notifyListeners();
    });
  }

  Uint8List? imageBytes(String id) {
    if (_disposed || !isStoredThemeImageId(id)) return null;
    final bytes = _imageCache[id];
    if (bytes != null) return bytes;
    if (!_missing.contains(id) && _loading.add(id)) unawaited(_readImage(id));
    return null;
  }

  Future<void> _readImage(String id) async {
    Uint8List? bytes;
    try {
      bytes = await _images.read(id);
    } catch (_) {
      appLogger.warn('Could not read a chat background picture');
    } finally {
      _loading.remove(id);
    }
    if (_disposed) return;
    if (bytes == null || bytes.isEmpty || bytes.length > maxThemeBackgroundBytes) {
      if (_missing.length >= _maxMissingIds) _missing.remove(_missing.first);
      _missing.add(id);
      return;
    }
    _remember(id, bytes);
    notifyListeners();
  }

  void _remember(String id, Uint8List bytes) {
    _imageCache.remove(id);
    _imageCache[id] = bytes.asUnmodifiableView();
    if (_imageCache.length > _maxCachedImages) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _missing.remove(id);
  }

  Future<String?> addImage(Uint8List bytes) async {
    final encoded = await _encodeImage(bytes);
    if (_disposed || encoded == null || encoded.isEmpty || encoded.length > maxThemeBackgroundBytes) {
      return null;
    }
    final id = crypto.sha256.convert(encoded).toString().substring(0, 20);
    await _serializeStore(() async {
      await _images.write(id, encoded);
      if (!_isInUse(id)) _draftImages.add(id);
      if (!_disposed) {
        _remember(id, encoded);
        notifyListeners();
      }
    });
    return id;
  }

  /// Converts exchange pictures before committing a theme to preferences.
  Future<CustomTheme> storeThemeImages(CustomTheme theme) async {
    // This operation runs only for an explicit import. Decode a single frame
    // for each icon and keep the existing named and asset replacements.
    final normalized = Map.of(theme.icons);
    for (final entry in theme.icons.entries) {
      final bytes = entry.value.imageBytes;
      if (bytes == null) continue;
      final encoded = await shrinkThemeIconImage(bytes);
      if (encoded == null) throw const FormatException('Unreadable theme icon');
      normalized[entry.key] = ThemeIconOverride.image(encoded);
    }
    final background = theme.chatBackground;
    final inline = background?.inlineImage;
    if (inline == null) return theme.copyWith(icons: Map.unmodifiable(normalized));
    final id = await addImage(inline);
    if (id == null) throw const FormatException('Unreadable theme background');
    return theme.copyWith(
      icons: Map.unmodifiable(normalized),
      chatBackground: background!.withStoredImage(id),
    );
  }

  Future<CustomTheme> embedThemeImages(CustomTheme theme) async {
    final background = theme.chatBackground;
    final id = background?.imageId;
    if (id == null) return theme;
    final bytes = _imageCache[id] ?? await _images.read(id);
    if (bytes == null) throw StateError('Theme picture is missing');
    return theme.copyWith(chatBackground: background!.withInlineImage(bytes));
  }

  bool _isInUse(String id) =>
      _byChat.values.any((value) => value.imageId == id) ||
      _settings.settings.customThemes.any((theme) => theme.chatBackground?.imageId == id);

  /// Runs after explicit editor actions. Pictures still held by an open draft
  /// stay protected for this service session.
  Future<void> collectGarbage() async {
    try {
      await _serializeStore(() async {
        for (final id in await _images.listIds()) {
          if (_draftImages.contains(id) || _isInUse(id)) continue;
          await _images.delete(id);
          _imageCache.remove(id);
        }
      });
    } catch (_) {
      appLogger.warn('Could not clean up unused chat backgrounds');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_settingsChanged);
    super.dispose();
  }
}

Future<Uint8List?> encodeChatBackgroundJxl(Uint8List bytes) async {
  ui.Image? image;
  try {
    image = await decodeThemePicture(bytes, ChatBackgroundService.maxImageSide);
    return await encodeJxlLossyFromUiImage(image, distance: ChatBackgroundService.jxlDistance);
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
  }
}
