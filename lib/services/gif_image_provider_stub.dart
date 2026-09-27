import 'package:flutter/painting.dart';

/// Web keeps the plain network image: there is no file system to cache in,
/// and the browser has an HTTP cache of its own.
ImageProvider gifImageProvider(String url) => NetworkImage(url);
