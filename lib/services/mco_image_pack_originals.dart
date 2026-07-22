import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:lottie/lottie.dart';

import '../helpers/mco_image_identity.dart';
import '../storage/mco_image_gallery_store.dart';
import '../storage/prefs_manager.dart';

enum McoImageOriginalFormat { lottieJson, lottie, png, gif, jpg, jpeg }

McoImageOriginalFormat? mcoImageOriginalFormatForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.lottie.json')) {
    return McoImageOriginalFormat.lottieJson;
  }
  if (lower.endsWith('.lottie')) return McoImageOriginalFormat.lottie;
  if (lower.endsWith('.png')) return McoImageOriginalFormat.png;
  if (lower.endsWith('.gif')) return McoImageOriginalFormat.gif;
  if (lower.endsWith('.jpg')) return McoImageOriginalFormat.jpg;
  if (lower.endsWith('.jpeg')) return McoImageOriginalFormat.jpeg;
  return null;
}

bool isMcoImageOriginalFileName(String fileName) {
  return mcoImageOriginalFormatForFileName(fileName) != null;
}

int compareMcoImageOriginalFileNames(String left, String right) {
  final byFormat = mcoImageOriginalPriority(left).compareTo(
    mcoImageOriginalPriority(right),
  );
  if (byFormat != 0) return byFormat;
  return _compareNaturalStrings(left, right);
}

int _compareNaturalStrings(String left, String right) {
  final a = left.toLowerCase();
  final b = right.toLowerCase();
  var ai = 0;
  var bi = 0;
  while (ai < a.length && bi < b.length) {
    final aDigit = _isAsciiDigit(a.codeUnitAt(ai));
    final bDigit = _isAsciiDigit(b.codeUnitAt(bi));
    if (aDigit && bDigit) {
      final aStart = ai;
      final bStart = bi;
      while (ai < a.length && _isAsciiDigit(a.codeUnitAt(ai))) {
        ai++;
      }
      while (bi < b.length && _isAsciiDigit(b.codeUnitAt(bi))) {
        bi++;
      }
      final rawA = a.substring(aStart, ai);
      final rawB = b.substring(bStart, bi);
      final aRun = rawA.replaceFirst(RegExp(r'^0+'), '');
      final bRun = rawB.replaceFirst(RegExp(r'^0+'), '');
      final normalizedA = aRun.isEmpty ? '0' : aRun;
      final normalizedB = bRun.isEmpty ? '0' : bRun;
      final byLength = normalizedA.length.compareTo(normalizedB.length);
      if (byLength != 0) return byLength;
      final byValue = normalizedA.compareTo(normalizedB);
      if (byValue != 0) return byValue;
      final byRunLength = rawA.length.compareTo(rawB.length);
      if (byRunLength != 0) return byRunLength;
      continue;
    }
    final byCharacter = a.codeUnitAt(ai).compareTo(b.codeUnitAt(bi));
    if (byCharacter != 0) return byCharacter;
    ai++;
    bi++;
  }
  return (a.length - ai).compareTo(b.length - bi);
}

bool _isAsciiDigit(int codeUnit) => codeUnit >= 48 && codeUnit <= 57;

int mcoImageOriginalPriority(String fileName) {
  return switch (mcoImageOriginalFormatForFileName(fileName)) {
    McoImageOriginalFormat.lottieJson => 0,
    McoImageOriginalFormat.lottie => 1,
    McoImageOriginalFormat.png => 2,
    McoImageOriginalFormat.gif => 3,
    McoImageOriginalFormat.jpg => 4,
    McoImageOriginalFormat.jpeg => 5,
    null => 6,
  };
}

Map<String, List<String>> decodeMcoImageOriginalsIndex(Object? value) {
  if (value is! Map<String, dynamic>) return const {};
  return {
    for (final entry in value.entries)
      if (entry.value is String)
        entry.key: [entry.value as String]
      else if (entry.value is List)
        entry.key: [
          for (final candidate in entry.value as List<dynamic>)
            if (candidate is String) candidate,
        ],
  };
}

bool mcoImageOriginalsIndexNeedsRebuild(Object? value) {
  if (value is! Map<String, dynamic>) return true;
  for (final candidates in value.values) {
    if (candidates is String) return true;
    if (candidates is! List ||
        candidates.isEmpty ||
        candidates.any((candidate) => candidate is! String)) {
      return true;
    }
  }
  return false;
}

class ResolvedMcoImageOriginal {
  final File file;
  final String relativePath;
  final McoImageOriginalFormat format;
  final LottieComposition? lottieComposition;

  const ResolvedMcoImageOriginal({
    required this.file,
    required this.relativePath,
    required this.format,
    this.lottieComposition,
  });

  bool get isLottie =>
      format == McoImageOriginalFormat.lottieJson ||
      format == McoImageOriginalFormat.lottie;
}

/// Resolves an MCOimg payload identity to the first valid original candidate
/// from an installed pack. Parsed Lottie compositions and invalid candidates
/// are cached so chat rebuilds do not repeatedly parse the same files.
class McoImagePackOriginals {
  McoImagePackOriginals._();

  static final McoImagePackOriginals instance = McoImagePackOriginals._();
  static const int _hashMemoLimit = 256;
  static const int _candidateCacheLimit = 128;
  static const int _lottieCacheLimit = 24;

  Map<String, List<String>>? _index;
  Future<void>? _loading;
  final Map<String, String?> _hashByText = {};
  final LinkedHashMap<String, Future<ResolvedMcoImageOriginal?>>
      _resolvedByPath = LinkedHashMap();
  final LinkedHashSet<String> _lottiePaths = LinkedHashSet();

  void replaceIndex(Map<String, List<String>> index) {
    _index = {
      for (final entry in index.entries) entry.key: List.of(entry.value),
    };
    _loading = null;
    _resolvedByPath.clear();
    _lottiePaths.clear();
  }

  Future<bool> hasOriginalForText(String text) async {
    return (await resolveOriginalForText(text)) != null;
  }

  Future<ResolvedMcoImageOriginal?> resolveOriginalForText(
    String text, {
    Set<String> excludedRelativePaths = const {},
  }) async {
    await _ensureLoaded();
    final index = _index;
    if (index == null || index.isEmpty) return null;
    final hash = _hashForText(text);
    if (hash == null) return null;

    final candidates = index[hash];
    if (candidates == null) return null;
    return resolveOriginalCandidates(
      candidates,
      excludedRelativePaths: excludedRelativePaths,
    );
  }

  Future<ResolvedMcoImageOriginal?> resolveOriginalCandidates(
    Iterable<String> candidates, {
    Set<String> excludedRelativePaths = const {},
  }) async {
    for (final relativePath in candidates) {
      if (excludedRelativePaths.contains(relativePath)) continue;
      final resolved = await _resolveCachedCandidate(relativePath);
      if (resolved != null) return resolved;
    }
    return null;
  }

  Future<ResolvedMcoImageOriginal?> _resolveCachedCandidate(
    String relativePath,
  ) {
    final existing = _resolvedByPath.remove(relativePath);
    if (existing != null) {
      _resolvedByPath[relativePath] = existing;
      if (_lottiePaths.remove(relativePath)) {
        _lottiePaths.add(relativePath);
      }
      return existing;
    }

    final future = _resolveCandidate(relativePath);
    _resolvedByPath[relativePath] = future;
    _trimCandidateCache();
    unawaited(
      future.then((resolved) {
        if (resolved?.isLottie != true ||
            !_resolvedByPath.containsKey(relativePath)) {
          return;
        }
        _lottiePaths
          ..remove(relativePath)
          ..add(relativePath);
        while (_lottiePaths.length > _lottieCacheLimit) {
          final oldest = _lottiePaths.first;
          _lottiePaths.remove(oldest);
          _resolvedByPath.remove(oldest);
        }
      }),
    );
    return future;
  }

  void _trimCandidateCache() {
    while (_resolvedByPath.length > _candidateCacheLimit) {
      final oldest = _resolvedByPath.keys.first;
      _resolvedByPath.remove(oldest);
      _lottiePaths.remove(oldest);
    }
  }

  String? _hashForText(String text) {
    var hash = _hashByText[text];
    if (!_hashByText.containsKey(text)) {
      hash = MCOImageIdentity.hashFromText(text);
      if (_hashByText.length >= _hashMemoLimit) _hashByText.clear();
      _hashByText[text] = hash;
    }
    return hash;
  }

  Future<ResolvedMcoImageOriginal?> _resolveCandidate(
    String relativePath,
  ) async {
    final format = mcoImageOriginalFormatForFileName(relativePath);
    if (format == null) return null;
    final packsDir = await MCOImageGalleryStore().packsDirectoryPath();
    final file = File(
      [packsDir, ...relativePath.split('/')].join(Platform.pathSeparator),
    );
    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      if (format == McoImageOriginalFormat.lottieJson ||
          format == McoImageOriginalFormat.lottie) {
        final composition = format == McoImageOriginalFormat.lottieJson
            ? LottieComposition.parseJsonBytes(bytes)
            : await LottieComposition.fromBytes(bytes);
        if (composition.bounds.width <= 0 || composition.bounds.height <= 0) {
          return null;
        }
        for (final asset in composition.images.values) {
          if (asset.loadedImage != null) continue;
          if (!asset.fileName.startsWith('data:')) return null;
          final data = Uri.parse(asset.fileName).data;
          if (data == null) return null;
          final codec = await ui.instantiateImageCodec(data.contentAsBytes());
          try {
            final frame = await codec.getNextFrame();
            asset.loadedImage = frame.image;
          } finally {
            codec.dispose();
          }
        }
        return ResolvedMcoImageOriginal(
          file: file,
          relativePath: relativePath,
          format: format,
          lottieComposition: composition,
        );
      }

      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width <= 0 || descriptor.height <= 0) return null;
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      return ResolvedMcoImageOriginal(
        file: file,
        relativePath: relativePath,
        format: format,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureLoaded() {
    if (_index != null) return Future.value();
    final pending = _loading;
    if (pending != null) return pending;
    final future = _load();
    _loading = future;
    return future;
  }

  Future<void> _load() async {
    try {
      final jsonString = PrefsManager.instance.getString(
        MCOImageGalleryStore.packOriginalsIndexKey,
      );
      if (jsonString != null && jsonString.isNotEmpty) {
        final decoded = jsonDecode(jsonString);
        if (decoded is Map<String, dynamic>) {
          _index = decodeMcoImageOriginalsIndex(decoded);
          if (mcoImageOriginalsIndexNeedsRebuild(decoded)) {
            try {
              await MCOImageGalleryStore().rebuildPackOriginalsIndex();
            } catch (_) {
              // Keep the readable legacy index if migration cannot run yet.
            }
          }
          return;
        }
      }
      await MCOImageGalleryStore().rebuildPackOriginalsIndex();
      _index ??= const {};
    } catch (_) {
      _index = const {};
    } finally {
      _loading = null;
    }
  }

}
