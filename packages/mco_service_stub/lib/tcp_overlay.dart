import 'package:flutter/widgets.dart';

// Optional transport hooks. Public builds have no native overlay dependency.
bool isMcoTcpOverlayEndpoint(String host) => false;

Future<Object?> openMcoTcpSocket({
  required String host,
  required int port,
  required Duration timeout,
}) async => null;

List<Widget> buildMcoTcpControls(
  BuildContext context, {
  required TextEditingController hostController,
  required bool enabled,
  VoidCallback? onChanged,
}) => const <Widget>[];
