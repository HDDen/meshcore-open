import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../screens/map_screen.dart';

/// Icon button that opens the map centred on a contact's own position.
///
/// Draws nothing at all for a contact without usable coordinates — an advert
/// carries 0,0 until its node has a fix, which is what [Contact.hasLocation]
/// rejects — so a caller can drop it into a row unconditionally.
///
/// The map is pushed on top of whatever opened it rather than replacing it, so
/// coming back lands on the same screen or dialog with its state intact. The
/// position only centres it: the contact already has a node marker there, and
/// the map's own highlight pin would just sit underneath it saying nothing.
class ContactMapButton extends StatelessWidget {
  /// Zoom the map opens at. It has to clear the map's own label threshold
  /// (`_labelZoomThreshold`, 14.0), or the node would sit there as a bare dot
  /// with no name against it — which is the whole point of going there.
  static const double _zoom = 15;

  final Contact contact;

  const ContactMapButton({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    final latitude = contact.latitude;
    final longitude = contact.longitude;
    if (!contact.hasLocation || latitude == null || longitude == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.map_outlined),
      tooltip: context.l10n.channelPath_viewMap,
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MapScreen(
            highlightPosition: LatLng(latitude, longitude),
            highlightZoom: _zoom,
            showHighlightPin: false,
          ),
        ),
      ),
    );
  }
}
