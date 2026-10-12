import 'package:flutter/material.dart';

import 'review_mode.dart';

/// Review mode stays unreachable in this fork: the simulated radio's
/// contacts, channels and messages would go into the application database,
/// and the cleanup in review_mode_storage.dart clears preferences only.
/// Flip this once the cleanup covers the database.
const bool reviewModeAvailable = false;

/// Hidden entry point: long-pressing [child] offers to enter review mode.
class ReviewModeLongPress extends StatelessWidget {
  final Widget child;

  const ReviewModeLongPress({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!reviewModeAvailable) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => enterReviewMode(context),
      child: child,
    );
  }
}
