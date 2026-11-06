import 'package:flutter/material.dart';

import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';

/// Repeaters and rooms require an admin session for location telemetry;
/// the map offers this unauthenticated action only to companions/sensors.
class ContactLocationRequestButton extends StatelessWidget {
  const ContactLocationRequestButton({
    super.key,
    required this.contact,
    required this.isConnected,
    required this.busy,
    required this.locating,
    required this.onPressed,
  });

  final Contact contact;
  final bool isConnected;
  final bool busy;
  final bool locating;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!contact.isActive ||
        (contact.type != advTypeChat && contact.type != advTypeSensor)) {
      return const SizedBox.shrink();
    }
    return OutlinedButton.icon(
      onPressed: isConnected && !busy ? onPressed : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      icon: locating
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.my_location, size: 18),
      label: Text(context.l10n.map_requestLocation),
    );
  }
}
