import 'package:flutter/widgets.dart';

import 'mcoa_bubble_surface.dart';

/// Additional message gap split into two independently addressable
/// halves. No width is imposed, so short bubbles retain their natural width.
class McoaMessageMetadataSpacing extends StatelessWidget {
  const McoaMessageMetadataSpacing({
    super.key,
    required this.height,
    this.messageBottomPadding = 0,
    this.metadataTopPadding = 0,
  });

  final double height;
  final double messageBottomPadding;
  final double metadataTopPadding;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      McoaMetadataBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: const ValueKey('mcoa-metadata-spacing-top'),
              height: height / 2,
            ),
            SizedBox(
              key: const ValueKey('mcoa-metadata-spacing-bottom'),
              height: height / 2,
            ),
            if (messageBottomPadding > 0) SizedBox(height: messageBottomPadding),
          ],
        ),
      ),
      if (metadataTopPadding > 0)
        SizedBox(
          key: const ValueKey('mcoa-metadata-top-padding'),
          height: metadataTopPadding,
        ),
    ],
  );
}
