import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:share_plus/share_plus.dart';

import 'mcoimg_codec.dart';
import '../widgets/mco_image_message.dart';

class MCOImageFileSaver {
  static Future<bool> savePng(MCOImage image) async {
    final bytes = await MCOImageMessage.renderPngBytes(image);
    final fileName = _fileName();
    try {
      final location = await file_selector.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'PNG image',
            extensions: ['png'],
            mimeTypes: ['image/png'],
          ),
        ],
      );
      if (location == null) return false;
      await XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: fileName,
      ).saveTo(location.path);
      return true;
    } catch (_) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
        ),
      );
      return true;
    }
  }

  static String _fileName() {
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'meshcore_canvas_$timestamp.png';
  }
}
