import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/path_helper.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../theme/mesh_theme.dart';
import 'mesh_ui.dart';
import 'signal_ui.dart';

Contact? _getRepeaterPrefixMatchNearLocation(
  List<Contact> contacts,
  List<int> pubkeyPrefix, {
  String? contactKeyHex,
  LatLng? searchPoint,
  bool preferFavorites = false,
}) {
  if (contactKeyHex != null) {
    for (final c in contacts) {
      if (c.publicKeyHex == contactKeyHex) {
        return c;
      }
    }
  }

  final candidates = contacts
      .where(
        (c) =>
            c.publicKey.length >= pubkeyPrefix.length &&
            listEquals(
              c.publicKey.sublist(0, pubkeyPrefix.length),
              pubkeyPrefix,
            ) &&
            (c.type == advTypeRepeater || c.type == advTypeRoom),
      )
      .toList();

  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    if (preferFavorites) {
      final favA = a.isFavorite ? 1 : 0;
      final favB = b.isFavorite ? 1 : 0;
      final favCompare = favB.compareTo(favA);
      if (favCompare != 0) return favCompare;
    }

    final seenCompare = b.lastSeen.compareTo(a.lastSeen);
    if (seenCompare != 0) return seenCompare;

    return a.publicKeyHex.compareTo(b.publicKeyHex);
  });

  if (searchPoint == null) {
    return candidates.first;
  }

  final distance = Distance();
  Contact best = candidates.first;
  var bestDistance = double.infinity;

  for (final c in candidates) {
    if (c.hasLocation && c.latitude != null && c.longitude != null) {
      final d = distance(searchPoint, LatLng(c.latitude!, c.longitude!));
      if (d < bestDistance) {
        bestDistance = d;
        best = c;
      }
    }
  }

  return best;
}

class SNRUi {
  final IconData icon;
  final Color color;
  final String text;
  const SNRUi(this.icon, this.color, this.text);
}

List<double> getSNRfromSF(int spreadingFactor) {
  switch (spreadingFactor) {
    case 7:
      return [4.0, -2.0, -4.0, -6.0];
    case 8:
      return [4.0, -4.0, -6.0, -8.0];
    case 9:
      return [4.0, -6.0, -8.0, -10.0];
    case 10:
      return [4.0, -8.0, -10.0, -13.0];
    case 11:
      return [4.0, -10.0, -12.5, -15.0];
    case 12:
      return [4.0, -12.5, -15.0, -18.0];
    default:
      return []; // Or throw Exception('Invalid SF: $spreadingFactor');
  }
}

SNRUi snrUiFromSNR(double? snr, int? spreadingFactor) {
  if (snr == null ||
      spreadingFactor == null ||
      spreadingFactor < 7 ||
      spreadingFactor > 12) {
    return const SNRUi(Icons.signal_cellular_off, Colors.grey, '—');
  }

  final snrLevels = getSNRfromSF(spreadingFactor);

  String text = '${snr.toStringAsFixed(1)} dB';
  final tier = snr >= snrLevels[0]
      ? 0
      : snr >= snrLevels[1]
      ? 1
      : snr >= snrLevels[2]
      ? 2
      : snr >= snrLevels[3]
      ? 3
      : 4;
  final signalUi = signalUiForStrengthTier(tier);

  return SNRUi(signalUi.icon, signalUi.color, text);
}

class SNRIndicator extends StatefulWidget {
  final MeshCoreConnector connector;

  const SNRIndicator({super.key, required this.connector});

  @override
  State<SNRIndicator> createState() => _SNRIndicatorState();
}

class _SNRIndicatorState extends State<SNRIndicator> {
  @override
  Widget build(BuildContext context) {
    final directRepeaters = widget.connector.directRepeaters;
    final directBestRepeaters = List.of(directRepeaters)
      ..sort((a, b) => (b.ranking).compareTo(a.ranking));
    final directRepeater = directBestRepeaters.isEmpty
        ? null
        : directBestRepeaters.first;

    final snrUi = snrUiFromSNR(
      directBestRepeaters.isNotEmpty ? directRepeater!.snr : null,
      widget.connector.currentSf,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      child: InkWell(
        onTap: directRepeater != null
            ? () => _showFullPathDialog(context, directBestRepeaters)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(snrUi.icon, size: 18, color: snrUi.color),
              Text(
                snrUi.text,
                style: TextStyle(fontSize: 12, color: snrUi.color),
              ),
              if (directRepeater != null)
                Text(
                  '${directRepeaters.length}: ${directRepeater.pubkeyPrefixHex}: ${_formatLastUpdated(directRepeater.lastUpdated)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLastUpdated(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.isNegative) {
      return "0s";
    }
    if (diff.inMinutes < 1) {
      return "${diff.inSeconds}s";
    }
    if (diff.inMinutes < 60) {
      return "${diff.inMinutes}m";
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return "${hours}h";
    }
    final days = diff.inDays;
    return "${days}d";
  }

  void _showFullPathDialog(
    BuildContext context,
    List<DirectRepeater> directBestRepeaters,
  ) {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.snrIndicator_nearByRepeaters),
        content: _RepeaterDialogList(
          connector: widget.connector,
          repeaters: directBestRepeaters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_close),
          ),
        ],
      ),
    );
  }
}

/// Scrollable repeater list used by the SNR indicator dialogs. Owns its own
/// [ScrollController] so the [Scrollbar] always has a position attached.
class _RepeaterDialogList extends StatefulWidget {
  final MeshCoreConnector connector;
  final List<DirectRepeater> repeaters;

  const _RepeaterDialogList({required this.connector, required this.repeaters});

  @override
  State<_RepeaterDialogList> createState() => _RepeaterDialogListState();
}

class _RepeaterDialogListState extends State<_RepeaterDialogList> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValidSelfLocation(double lat, double lon) {
    const double epsilon = 1e-6;
    return (lat.abs() > epsilon || lon.abs() > epsilon) &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lon >= -180.0 &&
        lon <= 180.0;
  }

  String _formatLastUpdated(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.isNegative) return "0s";
    if (diff.inMinutes < 1) return "${diff.inSeconds}s";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m";
    if (diff.inHours < 24) return "${diff.inHours}h";
    return "${diff.inDays}d";
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Scrollbar(
          controller: _controller,
          child: ListView.separated(
            controller: _controller,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: widget.repeaters.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final repeater = widget.repeaters[index];
              final allContacts = widget.connector.allContacts;

              final selfLat = widget.connector.selfLatitude;
              final selfLon = widget.connector.selfLongitude;

              LatLng? selfPoint;
              if (selfLat != null &&
                  selfLon != null &&
                  _isValidSelfLocation(selfLat, selfLon)) {
                selfPoint = LatLng(selfLat, selfLon);
              }

              final contact = _getRepeaterPrefixMatchNearLocation(
                allContacts,
                repeater.pubkeyPrefix,
                contactKeyHex: repeater.contactKeyHex,
                searchPoint: selfPoint,
                preferFavorites: true,
              );

              final name = contact?.name;
              final prefixLabel = PathHelper.formatHopHex(repeater.pubkeyPrefix);
              final snrColor = MeshTheme.snrColor(repeater.snr, blocked: false);

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    AvatarCircle(
                      name: name ?? prefixLabel,
                      size: 36,
                      color: snrColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name ?? prefixLabel,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            '${repeater.snr.toStringAsFixed(1)} dB • ${_formatLastUpdated(repeater.lastUpdated)}',
                            style: MeshTheme.mono(fontSize: 11, color: snrColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Variant of [SNRIndicator] that ranks by the signal of every repeater seen
/// as the last hop of ANY received packet (not just adverts). Backed by
/// `connector.activeRepeaters`; the dialog lists up to 10 repeaters, scrollable.
class SNRActivityIndicator extends StatefulWidget {
  final MeshCoreConnector connector;

  const SNRActivityIndicator({super.key, required this.connector});

  @override
  State<SNRActivityIndicator> createState() => _SNRActivityIndicatorState();
}

class _SNRActivityIndicatorState extends State<SNRActivityIndicator> {
  @override
  Widget build(BuildContext context) {
    final activeRepeaters = widget.connector.activeRepeaters;
    // Freshest activity on top.
    final recentRepeaters = List.of(activeRepeaters)
      ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    final latestRepeater = recentRepeaters.isEmpty
        ? null
        : recentRepeaters.first;

    final snrUi = snrUiFromSNR(
      recentRepeaters.isNotEmpty ? latestRepeater!.snr : null,
      widget.connector.currentSf,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: InkWell(
        onTap: latestRepeater != null
            ? () => _showActivityDialog(context, recentRepeaters)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(snrUi.icon, size: 18, color: snrUi.color),
              Text(
                snrUi.text,
                style: TextStyle(fontSize: 12, color: snrUi.color),
              ),
              if (latestRepeater != null)
                Text(
                  '${activeRepeaters.length}: ${latestRepeater.pubkeyPrefixHex}: ${_formatLastUpdated(latestRepeater.lastUpdated)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLastUpdated(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.isNegative) {
      return "0s";
    }
    if (diff.inMinutes < 1) {
      return "${diff.inSeconds}s";
    }
    if (diff.inMinutes < 60) {
      return "${diff.inMinutes}m";
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return "${hours}h";
    }
    final days = diff.inDays;
    return "${days}d";
  }

  void _showActivityDialog(
    BuildContext context,
    List<DirectRepeater> repeaters,
  ) {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.snrIndicator_nearByRepeaters),
        content: _RepeaterDialogList(
          connector: widget.connector,
          repeaters: repeaters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_close),
          ),
        ],
      ),
    );
  }
}
