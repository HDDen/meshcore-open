/// Putting a picture on the system clipboard. Flutter's own `Clipboard` carries
/// text only, and the plugins that carry pictures each want a native build step
/// and a content provider in the Android manifest, so this covers the one
/// platform where it takes nothing but system calls: Windows, through
/// `dart:ffi`. Everywhere else `ImageClipboard.isSupported` is false and the
/// caller hands the picture over some other way.
library;

export 'image_clipboard_stub.dart'
    if (dart.library.io) 'image_clipboard_io.dart';
