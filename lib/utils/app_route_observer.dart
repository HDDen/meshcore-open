import 'package:flutter/material.dart';

/// Shared route observer for screens that need to react when another route
/// is pushed on top of them without being disposed.
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
