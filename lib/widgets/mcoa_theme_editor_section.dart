import 'package:flutter/material.dart';

import 'mesh_ui.dart';

/// A theme section keeps its editors mounted when folded, preserving input.
class McoaThemeEditorSection extends StatelessWidget {
  const McoaThemeEditorSection({
    super.key,
    required this.id,
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String id;
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        expanded: expanded,
        child: InkWell(
          key: ValueKey('theme-section-$id-toggle'),
          onTap: onToggle,
          child: SectionHeader(
            title,
            trailing: ExcludeSemantics(
              child: Icon(expanded ? Icons.remove : Icons.add, size: 20),
            ),
          ),
        ),
      ),
      Visibility(
        visible: expanded,
        maintainState: true,
        child: child,
      ),
    ],
  );
}
