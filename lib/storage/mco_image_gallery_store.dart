import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../helpers/channel_app_data_helper.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../models/mco_image_gallery_item.dart';
import '../models/mco_image_pack.dart';
import '../widgets/mco_image_message.dart';
import 'prefs_manager.dart';

class MCOImageGalleryStore {
  static const String _key = 'mco_image_gallery_items';
  static const String _collapsedGroupsKey =
      'mco_image_gallery_collapsed_groups';
  static const String _packsDirectoryName = 'mcoimg_packs';
  static const String _bundledPacksDirectory = 'assets/mcopacks/';
  static Future<void>? _bundledPacksInstallFuture;

  Future<List<MCOImageGalleryItem>> loadItems() async {
    await ensureBundledPacksInstalled();
    final jsonString = PrefsManager.instance.getString(_key);
    if (jsonString == null || jsonString.isEmpty) {
      return _loadPackItems();
    }
    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      final items = <MCOImageGalleryItem>[];
      var migrated = false;
      for (final entry in jsonList) {
        if (entry is! Map<String, dynamic>) continue;
        final rawGroupId = entry['groupId'];
        if (rawGroupId is! String || rawGroupId.trim().isEmpty) {
          migrated = true;
        }
        final item = _fromJson(entry);
        if (item != null) items.add(item);
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (migrated) {
        unawaited(saveItems(items));
      }
      items.addAll(await _loadPackItems());
      return items;
    } catch (_) {
      return _loadPackItems();
    }
  }

  Future<void> saveItems(List<MCOImageGalleryItem> items) async {
    final jsonList = items
        .where((item) => !item.isPackItem)
        .map(_toJson)
        .toList();
    await PrefsManager.instance.setString(_key, jsonEncode(jsonList));
  }

  Future<Set<String>> loadCollapsedGroupIds() async {
    final jsonString = PrefsManager.instance.getString(_collapsedGroupsKey);
    if (jsonString == null || jsonString.isEmpty) return {};
    try {
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      return jsonList
          .whereType<String>()
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveCollapsedGroupIds(Set<String> groupIds) async {
    final jsonList = groupIds
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList()
      ..sort();
    await PrefsManager.instance.setString(
      _collapsedGroupsKey,
      jsonEncode(jsonList),
    );
  }

  Future<void> ensureBundledPacksInstalled() async {
    final existing = _bundledPacksInstallFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final future = _installBundledPacks();
    _bundledPacksInstallFuture = future;
    await future;
  }

  Future<void> _installBundledPacks() async {
    final assetPaths = await _loadBundledPackAssetPaths();
    if (assetPaths.isEmpty) return;

    final packsDir = await _packsDirectory();
    for (final assetPath in assetPaths) {
      try {
        final data = await rootBundle.load(assetPath);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final folderName = _packFolderNameFromBytes(bytes);
        final packDir = Directory(_joinPath(packsDir.path, folderName));
        if (await packDir.exists()) continue;
        await importPack(bytes);
      } catch (_) {
        continue;
      }
    }
  }

  Future<MCOImagePackMetadata> importPack(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? infoFile;
    for (final file in archive.files) {
      if (file.isFile && _normalizedZipPath(file.name) == 'info.json') {
        infoFile = file;
        break;
      }
    }
    if (infoFile == null) {
      throw const FormatException('MCOimg pack info.json is missing');
    }

    final infoJson = jsonDecode(utf8.decode(_archiveFileBytes(infoFile)));
    if (infoJson is! Map<String, dynamic>) {
      throw const FormatException('MCOimg pack info.json is invalid');
    }

    final folderName = _packFolderName(infoJson);
    final metadata = MCOImagePackMetadata.fromJson(
      infoJson,
      folderName: folderName,
    );
    final imagePairs = _packImagePairs(archive.files);
    if (imagePairs.isEmpty) {
      throw const FormatException('MCOimg pack does not contain images');
    }

    final packsDir = await _packsDirectory();
    final packDir = Directory(_joinPath(packsDir.path, folderName));
    if (await packDir.exists()) {
      await packDir.delete(recursive: true);
    }
    await packDir.create(recursive: true);

    await File(_joinPath(packDir.path, 'info.json')).writeAsBytes(
      _archiveFileBytes(infoFile),
      flush: true,
    );

    for (final pair in imagePairs) {
      final imageDir = Directory(
        _joinPath(_joinPath(packDir.path, 'images'), pair.directoryName),
      );
      await imageDir.create(recursive: true);
      await File(_joinPath(imageDir.path, pair.pngFileName)).writeAsBytes(
        _archiveFileBytes(pair.pngFile),
        flush: true,
      );
      await File(_joinPath(imageDir.path, pair.binFileName)).writeAsBytes(
        _archiveFileBytes(pair.binFile),
        flush: true,
      );
    }

    return metadata;
  }

  Future<List<String>> _loadBundledPackAssetPaths() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest
          .listAssets()
          .where(
            (path) =>
                path.startsWith(_bundledPacksDirectory) &&
                path.toLowerCase().endsWith('.mcoimg.pack'),
          )
          .toList();
      paths.sort(_compareNaturalStrings);
      return paths;
    } catch (_) {
      return const [];
    }
  }

  String _packFolderNameFromBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (!file.isFile || _normalizedZipPath(file.name) != 'info.json') {
        continue;
      }
      final infoJson = jsonDecode(utf8.decode(_archiveFileBytes(file)));
      if (infoJson is! Map<String, dynamic>) {
        throw const FormatException('MCOimg pack info.json is invalid');
      }
      return _packFolderName(infoJson);
    }
    throw const FormatException('MCOimg pack info.json is missing');
  }

  Future<List<MCOImagePackMetadata>> loadPacks() async {
    final packsDir = await _packsDirectory(create: false);
    if (!await packsDir.exists()) return [];

    final packs = <MCOImagePackMetadata>[];
    await for (final entity in packsDir.list()) {
      if (entity is! Directory) continue;
      final infoFile = File(_joinPath(entity.path, 'info.json'));
      if (!await infoFile.exists()) continue;
      try {
        final infoJson = jsonDecode(await infoFile.readAsString());
        if (infoJson is! Map<String, dynamic>) continue;
        packs.add(
          MCOImagePackMetadata.fromJson(
            infoJson,
            folderName: _fileNameFromPath(entity.path),
          ),
        );
      } catch (_) {
        continue;
      }
    }

    packs.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return packs;
  }

  Future<void> removePack(MCOImagePackMetadata pack) async {
    final packsDir = await _packsDirectory(create: false);
    final packDir = Directory(_joinPath(packsDir.path, pack.folderName));
    if (await packDir.exists()) {
      await packDir.delete(recursive: true);
    }
  }

  Future<MCOImageGalleryItem> createFromText(String text) async {
    final trimmed = text.trimLeft();
    final isV3 = MCOImageV3Codec.isTextPayload(trimmed);
    final binaryPayload = isV3
        ? MCOImageV3Codec.appPayloadWithoutSenderFromText(trimmed)
        : MCOImageCodec.binaryPayloadFromText(trimmed);
    final image = isV3
        ? MCOImageV3Codec().decodeAppPayloadWithoutSender(binaryPayload)
        : MCOImageCodec().decode(
            MCOImageCodec.textFromBinaryPayload(binaryPayload),
          );
    final payloadInfo = isV3
        ? null
        : MCOImageCodec.inspectPayload(
            MCOImageCodec.textFromBinaryPayload(binaryPayload),
          );
    final pngBytes = await MCOImageMessage.renderPngBytes(image, cellSize: 1);
    final now = DateTime.now();
    return MCOImageGalleryItem(
      id: '${now.microsecondsSinceEpoch}',
      createdAt: now,
      groupId: MCOImageGalleryItem.commonGroupId,
      binaryPayload: binaryPayload,
      pngBytes: pngBytes,
      width: image.width,
      height: image.height,
      byteLength: binaryPayload.length,
      usedColorCount: image.pixels.toSet().length,
      codecVersion: isV3
          ? ChannelAppDataHelper.mcoImageV3Version
          : payloadInfo?.version ?? _codecVersionForImage(image),
      paletteProfile: image.paletteProfile,
    );
  }

  Future<void> addFromText(String text) async {
    final item = await createFromText(text);
    final items = await loadItems();
    final duplicateIndex = items.indexWhere(
      (entry) => _samePayload(entry.binaryPayload, item.binaryPayload),
    );
    if (duplicateIndex >= 0) {
      items[duplicateIndex] = item.copyWith(
        groupId: MCOImageGalleryItem.commonGroupId,
        clearGroupName: true,
        showPngFallback: items[duplicateIndex].showPngFallback,
      );
    } else {
      items.insert(0, item);
    }
    await saveItems(items);
  }

  Map<String, dynamic> _toJson(MCOImageGalleryItem item) {
    return {
      'id': item.id,
      'createdAt': item.createdAt.millisecondsSinceEpoch,
      'groupId': item.groupId,
      if (item.groupName != null && item.groupName!.isNotEmpty)
        'groupName': item.groupName,
      'binaryPayload': base64Encode(item.binaryPayload),
      'pngBytes': base64Encode(item.pngBytes),
      'width': item.width,
      'height': item.height,
      'byteLength': item.byteLength,
      'usedColorCount': item.usedColorCount,
      'codecVersion': item.codecVersion,
      'paletteProfile': item.paletteProfile.name,
      'showPngFallback': item.showPngFallback,
    };
  }

  MCOImageGalleryItem? _fromJson(Map<String, dynamic> json) {
    try {
      final profileName = json['paletteProfile'] as String? ?? '';
      final profile = PaletteProfile.values.firstWhere(
        (entry) => entry.name == profileName,
        orElse: () => PaletteProfile.master64,
      );
      final binaryPayload = Uint8List.fromList(
        base64Decode(json['binaryPayload'] as String),
      );
      final pngBytes = Uint8List.fromList(
        base64Decode(json['pngBytes'] as String),
      );
      final codecVersion =
          json['codecVersion'] as int? ??
          _v3CodecVersionForPayload(binaryPayload) ??
          MCOImageCodec.inspectPayload(
            MCOImageCodec.textFromBinaryPayload(binaryPayload),
          )?.version ??
          1;
      final rawGroupId = json['groupId'];
      final rawGroupName = json['groupName'];
      final groupId = rawGroupId is String && rawGroupId.trim().isNotEmpty
          ? rawGroupId.trim()
          : MCOImageGalleryItem.commonGroupId;
      final groupName = rawGroupName is String && rawGroupName.trim().isNotEmpty
          ? rawGroupName.trim()
          : null;
      return MCOImageGalleryItem(
        id: json['id'] as String? ?? '${json['createdAt'] ?? 0}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          json['createdAt'] as int? ?? 0,
        ),
        groupId: groupId,
        groupName: groupName,
        binaryPayload: binaryPayload,
        pngBytes: pngBytes,
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        byteLength: json['byteLength'] as int? ?? binaryPayload.length,
        usedColorCount: json['usedColorCount'] as int? ?? 0,
        codecVersion: codecVersion,
        paletteProfile: profile,
        showPngFallback: json['showPngFallback'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  bool _samePayload(Uint8List left, Uint8List right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<List<MCOImageGalleryItem>> _loadPackItems() async {
    final packs = await loadPacks();
    if (packs.isEmpty) return [];

    final items = <MCOImageGalleryItem>[];
    for (final pack in packs) {
      final packDir = Directory(
        _joinPath((await _packsDirectory(create: false)).path, pack.folderName),
      );
      final imagesDir = Directory(_joinPath(packDir.path, 'images'));
      if (!await imagesDir.exists()) continue;

      final imageDirs = <Directory>[];
      await for (final entity in imagesDir.list()) {
        if (entity is Directory) imageDirs.add(entity);
      }
      imageDirs.sort(
        (a, b) => _compareNaturalStrings(
          _fileNameFromPath(a.path),
          _fileNameFromPath(b.path),
        ),
      );

      for (final imageDir in imageDirs) {
        final files = await imageDir.list().where((entity) {
          if (entity is! File) return false;
          final name = _fileNameFromPath(entity.path).toLowerCase();
          return _isPackPreviewFileName(name) ||
              name.endsWith('.mcoimg.bin');
        }).toList();
        File? pngFile;
        File? binFile;
        for (final entity in files) {
          if (entity is! File) continue;
          final name = _fileNameFromPath(entity.path).toLowerCase();
          if (pngFile == null && _isPackPreviewFileName(name)) {
            pngFile = entity;
          } else if (binFile == null && name.endsWith('.mcoimg.bin')) {
            binFile = entity;
          }
        }
        if (pngFile == null || binFile == null) continue;

        try {
          final binaryPayload = await binFile.readAsBytes();
          final pngBytes = await pngFile.readAsBytes();
          final decoded = _decodeGalleryPayload(binaryPayload);
          final stat = await binFile.stat();
          items.add(
            MCOImageGalleryItem(
              id:
                  'pack:${pack.folderName}:${_fileNameFromPath(imageDir.path)}',
              createdAt: stat.modified,
              groupId: pack.groupId,
              groupName: pack.groupTitle,
              packFolderName: pack.folderName,
              previewMaxSize: pack.maxImageSize,
              binaryPayload: binaryPayload,
              pngBytes: pngBytes,
              width: decoded.image.width,
              height: decoded.image.height,
              byteLength: binaryPayload.length,
              usedColorCount: decoded.image.pixels.toSet().length,
              codecVersion: decoded.codecVersion,
              paletteProfile: decoded.image.paletteProfile,
            ),
          );
        } catch (_) {
          continue;
        }
      }
    }
    return items;
  }

  _DecodedGalleryPayload _decodeGalleryPayload(Uint8List binaryPayload) {
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      binaryPayload,
    );
    if (appPayload?.subtypeVersion ==
        ChannelAppDataHelper.mcoImageV3SubtypeVersion) {
      return _DecodedGalleryPayload(
        image: MCOImageV3Codec().decodeAppPayloadWithoutSender(binaryPayload),
        codecVersion: ChannelAppDataHelper.mcoImageV3Version,
      );
    }

    final textPayload = MCOImageCodec.textFromBinaryPayload(binaryPayload);
    final image = MCOImageCodec().decode(textPayload);
    final payloadInfo = MCOImageCodec.inspectPayload(textPayload);
    return _DecodedGalleryPayload(
      image: image,
      codecVersion: payloadInfo?.version ?? _codecVersionForImage(image),
    );
  }

  Future<Directory> _packsDirectory({bool create = true}) async {
    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory(_joinPath(baseDir.path, _packsDirectoryName));
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _packFolderName(Map<String, dynamic> infoJson) {
    final id = (infoJson['id'] as String?)?.trim();
    final version = (infoJson['ver'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      throw const FormatException('MCOimg pack id is missing');
    }
    if (version == null || version.isEmpty) {
      throw const FormatException('MCOimg pack version is missing');
    }
    final author = (infoJson['author'] as String?)?.trim();
    return 'mcoimgpack_'
        '${_sanitizePathSegment(author?.isNotEmpty == true ? author! : 'unknown')}_'
        '${_sanitizePathSegment(id)}_'
        '${_sanitizePathSegment(version)}';
  }

  List<_PackImagePair> _packImagePairs(List<ArchiveFile> files) {
    final byDirectory = <String, _MutablePackImagePair>{};
    for (final file in files) {
      if (!file.isFile) continue;
      final path = _normalizedZipPath(file.name);
      final parts = path.split('/');
      if (parts.length < 3 || parts.first != 'images') continue;
      final directoryName = _sanitizePathSegment(parts[1]);
      if (directoryName.isEmpty) continue;
      final fileName = _sanitizePathSegment(parts.last);
      final lowerFileName = fileName.toLowerCase();
      final pair = byDirectory.putIfAbsent(
        directoryName,
        () => _MutablePackImagePair(directoryName),
      );
      if (_isPackPreviewFileName(lowerFileName) && pair.pngFile == null) {
        pair.pngFile = file;
        pair.pngFileName = fileName;
      } else if (lowerFileName.endsWith('.mcoimg.bin') &&
          pair.binFile == null) {
        pair.binFile = file;
        pair.binFileName = fileName;
      }
    }

    final pairs = <_PackImagePair>[];
    for (final pair in byDirectory.values) {
      if (pair.pngFile == null || pair.binFile == null) continue;
      pairs.add(
        _PackImagePair(
          directoryName: pair.directoryName,
          pngFile: pair.pngFile!,
          pngFileName: pair.pngFileName!,
          binFile: pair.binFile!,
          binFileName: pair.binFileName!,
        ),
      );
    }
    pairs.sort(
      (a, b) => _compareNaturalStrings(a.directoryName, b.directoryName),
    );
    return pairs;
  }

  Uint8List _archiveFileBytes(ArchiveFile file) {
    return file.content;
  }

  bool _isPackPreviewFileName(String fileName) {
    return fileName.endsWith('.png') ||
        fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.gif');
  }

  String _normalizedZipPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized
        .split('/')
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .join('/');
  }

  String _sanitizePathSegment(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'item' : cleaned;
  }

  String _joinPath(String left, String right) {
    final separator = Platform.pathSeparator;
    if (left.endsWith(separator)) return '$left$right';
    return '$left$separator$right';
  }

  String _fileNameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }

  int _compareNaturalStrings(String left, String right) {
    final a = left.toLowerCase();
    final b = right.toLowerCase();
    var ai = 0;
    var bi = 0;

    while (ai < a.length && bi < b.length) {
      final ac = a.codeUnitAt(ai);
      final bc = b.codeUnitAt(bi);
      final aDigit = _isAsciiDigit(ac);
      final bDigit = _isAsciiDigit(bc);

      if (aDigit && bDigit) {
        final aStart = ai;
        final bStart = bi;
        while (ai < a.length && _isAsciiDigit(a.codeUnitAt(ai))) {
          ai++;
        }
        while (bi < b.length && _isAsciiDigit(b.codeUnitAt(bi))) {
          bi++;
        }

        final numericCompare = _compareNumericRuns(
          a.substring(aStart, ai),
          b.substring(bStart, bi),
        );
        if (numericCompare != 0) return numericCompare;
        continue;
      }

      if (ac != bc) return ac.compareTo(bc);
      ai++;
      bi++;
    }

    return (a.length - ai).compareTo(b.length - bi);
  }

  int _compareNumericRuns(String left, String right) {
    final normalizedLeft = _trimLeadingZeroes(left);
    final normalizedRight = _trimLeadingZeroes(right);
    final lengthCompare = normalizedLeft.length.compareTo(
      normalizedRight.length,
    );
    if (lengthCompare != 0) return lengthCompare;
    final valueCompare = normalizedLeft.compareTo(normalizedRight);
    if (valueCompare != 0) return valueCompare;
    return left.length.compareTo(right.length);
  }

  String _trimLeadingZeroes(String value) {
    var index = 0;
    while (index < value.length - 1 && value.codeUnitAt(index) == 48) {
      index++;
    }
    return value.substring(index);
  }

  bool _isAsciiDigit(int codeUnit) {
    return codeUnit >= 48 && codeUnit <= 57;
  }

  int _codecVersionForImage(MCOImage image) {
    return switch (image.encodingVersion) {
      MCOImageEncodingVersion.v1Legacy => 1,
      MCOImageEncodingVersion.v2 => 2,
      MCOImageEncodingVersion.v3 => ChannelAppDataHelper.mcoImageV3Version,
    };
  }

  int? _v3CodecVersionForPayload(Uint8List payload) {
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      payload,
    );
    if (appPayload?.subtypeVersion !=
        ChannelAppDataHelper.mcoImageV3SubtypeVersion) {
      return null;
    }
    return ChannelAppDataHelper.mcoImageV3Version;
  }
}

class _DecodedGalleryPayload {
  final MCOImage image;
  final int codecVersion;

  const _DecodedGalleryPayload({
    required this.image,
    required this.codecVersion,
  });
}

class _MutablePackImagePair {
  final String directoryName;
  ArchiveFile? pngFile;
  String? pngFileName;
  ArchiveFile? binFile;
  String? binFileName;

  _MutablePackImagePair(this.directoryName);
}

class _PackImagePair {
  final String directoryName;
  final ArchiveFile pngFile;
  final String pngFileName;
  final ArchiveFile binFile;
  final String binFileName;

  const _PackImagePair({
    required this.directoryName,
    required this.pngFile,
    required this.pngFileName,
    required this.binFile,
    required this.binFileName,
  });
}
