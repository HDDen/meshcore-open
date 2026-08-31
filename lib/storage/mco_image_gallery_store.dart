import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../helpers/channel_app_data_helper.dart';
import '../helpers/mco_image_identity.dart';
import '../helpers/mcoimg_codec.dart';
import '../helpers/mcoimg_v3_codec.dart';
import '../helpers/mcoimg_v4_codec.dart';
import '../helpers/mcoimg_v4_model.dart';
import '../models/mco_image_gallery_item.dart';
import '../models/mco_image_pack.dart';
import '../services/mco_image_pack_originals.dart';
import '../widgets/mco_image_message.dart';
import 'prefs_manager.dart';

class MCOImageGalleryStore {
  static const String _key = 'mco_image_gallery_items';
  static const String _collapsedGroupsKey =
      'mco_image_gallery_collapsed_groups';
  static const String _packsDirectoryName = 'mcoimg_packs';
  static const String _bundledPacksDirectory = 'assets/mcopacks/';

  /// Persisted "identity hash -> ordered pack original paths" table; see
  /// [rebuildPackOriginalsIndex] and [McoImagePackOriginals].
  static const String packOriginalsIndexKey = 'mco_image_pack_originals_index';
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
    final jsonList =
        groupIds
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
    if (_packOriginalsIndexNeedsRebuild()) {
      await rebuildPackOriginalsIndex();
    }
  }

  bool _packOriginalsIndexNeedsRebuild() {
    final encoded = PrefsManager.instance.getString(packOriginalsIndexKey);
    if (encoded == null || encoded.isEmpty) return true;
    try {
      final decoded = jsonDecode(encoded);
      return mcoImageOriginalsIndexNeedsRebuild(decoded);
    } catch (_) {
      return true;
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

    await File(
      _joinPath(packDir.path, 'info.json'),
    ).writeAsBytes(_archiveFileBytes(infoFile), flush: true);

    for (final pair in imagePairs) {
      final imageDir = Directory(
        _joinPath(_joinPath(packDir.path, 'images'), pair.directoryName),
      );
      await imageDir.create(recursive: true);
      for (final original in pair.originals) {
        await File(
          _joinPath(imageDir.path, original.fileName),
        ).writeAsBytes(_archiveFileBytes(original.file), flush: true);
      }
      await File(
        _joinPath(imageDir.path, pair.binFileName),
      ).writeAsBytes(_archiveFileBytes(pair.binFile), flush: true);
      final md5File = pair.md5File;
      final md5FileName = pair.md5FileName;
      if (md5File != null && md5FileName != null) {
        await File(
          _joinPath(imageDir.path, md5FileName),
        ).writeAsBytes(_archiveFileBytes(md5File), flush: true);
      }
    }

    await rebuildPackOriginalsIndex();
    return metadata;
  }

  /// Absolute path of the installed packs directory.
  Future<String> packsDirectoryPath() async {
    return (await _packsDirectory(create: false)).path;
  }

  /// Rebuilds the persisted "identity hash -> ordered original files" table
  /// over all
  /// installed packs. Hashes come from the *.md5 file inside each image
  /// folder when present (precomputed by pack tooling) and are otherwise
  /// computed from the image's .mcoimg.bin using the canonical
  /// [MCOImageIdentity] formula. Called on pack install/remove so message
  /// rendering never rescans the disk.
  Future<void> rebuildPackOriginalsIndex() async {
    final index = <String, List<String>>{};
    final packsDir = await _packsDirectory(create: false);
    if (await packsDir.exists()) {
      await for (final packEntity in packsDir.list()) {
        if (packEntity is! Directory) continue;
        final packFolderName = _fileNameFromPath(packEntity.path);
        final imagesDir = Directory(_joinPath(packEntity.path, 'images'));
        if (!await imagesDir.exists()) continue;

        await for (final imageEntity in imagesDir.list()) {
          if (imageEntity is! Directory) continue;
          final imageDirName = _fileNameFromPath(imageEntity.path);
          String? hash;
          final originalFileNames = <String>[];
          File? binFile;

          await for (final entity in imageEntity.list()) {
            if (entity is! File) continue;
            final fileName = _fileNameFromPath(entity.path);
            final lower = fileName.toLowerCase();
            if (lower.endsWith('.md5')) {
              if (hash == null) {
                try {
                  final value = (await entity.readAsString())
                      .trim()
                      .toLowerCase();
                  if (MCOImageIdentity.isValidHash(value)) hash = value;
                } catch (_) {
                  // Ignore unreadable hash files; fall back to computing.
                }
              }
            } else if (isMcoImageOriginalFileName(lower)) {
              originalFileNames.add(fileName);
            } else if (lower.endsWith('.mcoimg.bin')) {
              binFile ??= entity;
            }
          }

          if (originalFileNames.isEmpty) continue;
          if (hash == null && binFile != null) {
            try {
              hash = MCOImageIdentity.hashFromBinaryPayload(
                await binFile.readAsBytes(),
              );
            } catch (_) {
              continue;
            }
          }
          if (hash == null) continue;
          originalFileNames.sort(_compareOriginalFileNames);
          index[hash] = [
            for (final originalFileName in originalFileNames)
              '$packFolderName/images/$imageDirName/$originalFileName',
          ];
        }
      }
    }

    await PrefsManager.instance.setString(
      packOriginalsIndexKey,
      jsonEncode(index),
    );
    McoImagePackOriginals.instance.replaceIndex(index);
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

    packs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return packs;
  }

  Future<void> removePack(MCOImagePackMetadata pack) async {
    final packsDir = await _packsDirectory(create: false);
    final packDir = Directory(_joinPath(packsDir.path, pack.folderName));
    if (await packDir.exists()) {
      await packDir.delete(recursive: true);
    }
    await rebuildPackOriginalsIndex();
  }

  Future<MCOImageGalleryItem> createFromText(String text) async {
    final trimmed = text.trimLeft();
    final isV4 = MCOImageV4Codec.isTextPayload(trimmed);
    final isV3 = MCOImageV3Codec.isTextPayload(trimmed);
    final MCOImage image;
    final Uint8List binaryPayload;
    if (isV4) {
      final codec = const MCOImageV4Codec();
      final body = codec.stripTransportTail(codec.bodyFromText(trimmed));
      final decoded = codec.decodeBody(body);
      binaryPayload = ChannelAppDataHelper.appPayloadWithoutSender(
        subtypeId: ChannelAppDataHelper.mcoImageSubtype,
        version: ChannelAppDataHelper.mcoImageV4Version,
        body: body,
      );
      image = _v4Preview(decoded);
    } else if (isV3) {
      binaryPayload = MCOImageV3Codec.appPayloadWithoutSenderFromText(trimmed);
      image = MCOImageV3Codec().decodeAppPayloadWithoutSender(binaryPayload);
    } else {
      binaryPayload = MCOImageCodec.binaryPayloadFromText(trimmed);
      image = MCOImageCodec().decode(
        MCOImageCodec.textFromBinaryPayload(binaryPayload),
      );
    }
    final payloadInfo = isV3 || isV4
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
      usedColorCount: isV4
          ? (image as MCOImageV4Preview).document.palette.length
          : image.pixels.toSet().length,
      codecVersion: isV4
          ? ChannelAppDataHelper.mcoImageV4Version
          : isV3
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
      'originalFileName': item.originalFileName,
      if (item.originalRelativePaths.isNotEmpty)
        'originalRelativePaths': item.originalRelativePaths,
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
          _appCodecVersionForPayload(binaryPayload) ??
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
        originalFileName: json['originalFileName'] as String? ?? 'mcoimg.png',
        originalRelativePaths: [
          for (final path
              in json['originalRelativePaths'] as List<dynamic>? ?? const [])
            if (path is String) path,
        ],
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
          return isMcoImageOriginalFileName(name) ||
              name.endsWith('.mcoimg.bin');
        }).toList();
        File? binFile;
        final originalFileNames = <String>[];
        for (final entity in files) {
          if (entity is! File) continue;
          final fileName = _fileNameFromPath(entity.path);
          final name = fileName.toLowerCase();
          if (isMcoImageOriginalFileName(name)) {
            originalFileNames.add(fileName);
          } else if (binFile == null && name.endsWith('.mcoimg.bin')) {
            binFile = entity;
          }
        }
        if (binFile == null || originalFileNames.isEmpty) continue;

        try {
          final binaryPayload = await binFile.readAsBytes();
          final decoded = _decodeGalleryPayload(binaryPayload);
          originalFileNames.sort(_compareOriginalFileNames);
          final imageDirName = _fileNameFromPath(imageDir.path);
          final originalRelativePaths = [
            for (final fileName in originalFileNames)
              '${pack.folderName}/images/$imageDirName/$fileName',
          ];
          final stat = await binFile.stat();
          items.add(
            MCOImageGalleryItem(
              id: 'pack:${pack.folderName}:${_fileNameFromPath(imageDir.path)}',
              createdAt: stat.modified,
              groupId: pack.groupId,
              groupName: pack.groupTitle,
              packFolderName: pack.folderName,
              previewMaxSize: pack.maxImageSize,
              binaryPayload: binaryPayload,
              pngBytes: Uint8List(0),
              originalFileName: originalFileNames.first,
              originalRelativePaths: originalRelativePaths,
              width: decoded.image.width,
              height: decoded.image.height,
              byteLength: binaryPayload.length,
              usedColorCount: decoded.image is MCOImageV4Preview
                  ? (decoded.image as MCOImageV4Preview)
                        .document
                        .palette
                        .length
                  : decoded.image.pixels.toSet().length,
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
        ChannelAppDataHelper.mcoImageV4SubtypeVersion) {
      final decoded = const MCOImageV4Codec().decodeBody(appPayload!.body);
      return _DecodedGalleryPayload(
        image: _v4Preview(decoded),
        codecVersion: ChannelAppDataHelper.mcoImageV4Version,
      );
    }
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
        '${_sanitizePathSegment(id)}_'
        '${_sanitizePathSegment(author?.isNotEmpty == true ? author! : 'unknown')}_'
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
      if (isMcoImageOriginalFileName(lowerFileName)) {
        pair.originals.add(_PackOriginalFile(file: file, fileName: fileName));
      } else if (lowerFileName.endsWith('.mcoimg.bin') &&
          pair.binFile == null) {
        pair.binFile = file;
        pair.binFileName = fileName;
      } else if (lowerFileName.endsWith('.md5') && pair.md5File == null) {
        pair.md5File = file;
        pair.md5FileName = fileName;
      }
    }

    final pairs = <_PackImagePair>[];
    for (final pair in byDirectory.values) {
      if (pair.originals.isEmpty || pair.binFile == null) continue;
      pair.originals.sort(
        (a, b) => _compareOriginalFileNames(a.fileName, b.fileName),
      );
      pairs.add(
        _PackImagePair(
          directoryName: pair.directoryName,
          originals: List.of(pair.originals),
          binFile: pair.binFile!,
          binFileName: pair.binFileName!,
          md5File: pair.md5File,
          md5FileName: pair.md5FileName,
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

  int _compareOriginalFileNames(String left, String right) {
    return compareMcoImageOriginalFileNames(left, right);
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
      MCOImageEncodingVersion.v4 => ChannelAppDataHelper.mcoImageV4Version,
    };
  }

  int? _appCodecVersionForPayload(Uint8List payload) {
    final appPayload = ChannelAppDataHelper.tryDecodeAppPayloadWithoutSender(
      payload,
    );
    switch (appPayload?.subtypeVersion) {
      case ChannelAppDataHelper.mcoImageV3SubtypeVersion:
        return ChannelAppDataHelper.mcoImageV3Version;
      case ChannelAppDataHelper.mcoImageV4SubtypeVersion:
        return ChannelAppDataHelper.mcoImageV4Version;
      default:
        return null;
    }
  }

  MCOImageV4Preview _v4Preview(DecodedMCOImageV4 decoded) {
    final document = decoded.document;
    final background = document.backgroundColor == null
        ? -1
        : document.palette[document.backgroundColor!];
    return MCOImageV4Preview(
      document: document,
      paletteProfile: document.paletteProfile,
      pixels: List<int>.filled(document.width * document.height, background),
      transparentColor: background < 0 ? background : null,
    );
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
  final List<_PackOriginalFile> originals = [];
  ArchiveFile? binFile;
  String? binFileName;
  ArchiveFile? md5File;
  String? md5FileName;

  _MutablePackImagePair(this.directoryName);
}

class _PackImagePair {
  final String directoryName;
  final List<_PackOriginalFile> originals;
  final ArchiveFile binFile;
  final String binFileName;
  final ArchiveFile? md5File;
  final String? md5FileName;

  const _PackImagePair({
    required this.directoryName,
    required this.originals,
    required this.binFile,
    required this.binFileName,
    this.md5File,
    this.md5FileName,
  });
}

class _PackOriginalFile {
  final ArchiveFile file;
  final String fileName;

  const _PackOriginalFile({required this.file, required this.fileName});
}
