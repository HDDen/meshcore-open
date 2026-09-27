/// The provider `GifMessage` draws a GIF with, chosen at compile time: cached
/// on disk wherever `dart:io` exists, the plain network image on web.
library;

export 'gif_image_provider_stub.dart'
    if (dart.library.io) 'gif_image_provider_io.dart';
