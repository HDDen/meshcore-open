import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('U14 baseline: chips and avatars retain type cues, tint and '
        'idle behavior (dark=$dark)', (tester) async {
      const accent = MeshPalette.warn;
      const chipKey = ValueKey('chip-icon');
      const avatarKey = ValueKey('avatar-initials');
      await tester.pumpWidget(MaterialApp(
        theme: dark ? MeshTheme.dark() : MeshTheme.light(),
        home: const Scaffold(body: MeshCard(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(key: chipKey, label: 'Relay', color: accent,
                icon: Icons.cell_tower),
            StatusChip(label: 'Connected', color: accent),
            AvatarCircle(key: avatarKey, name: 'Alpha Beta', size: 44,
                color: accent),
            AvatarCircle(name: 'Room', icon: Icons.group, color: accent),
          ],
        ))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Relay'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('AB'), findsOneWidget);
      expect(find.byIcon(Icons.cell_tower), findsOneWidget);
      expect(find.byIcon(Icons.group), findsOneWidget);
      final chip = tester.widget<Container>(find.descendant(
        of: find.byKey(chipKey), matching: find.byType(Container),
      ).first).decoration! as BoxDecoration;
      final avatar = tester.widget<Container>(find.descendant(
        of: find.byKey(avatarKey), matching: find.byType(Container),
      ).first).decoration! as BoxDecoration;
      expect(chip.color, accent.withValues(alpha: 0.12));
      expect((chip.border! as Border).top.color,
          accent.withValues(alpha: 0.3));
      expect(avatar.color, accent.withValues(alpha: 0.14));
      expect(avatar.shape, BoxShape.circle);
      final card = Theme.of(tester.element(find.byKey(chipKey)))
          .colorScheme.surfaceContainerLow;
      final chipBackground = Color.alphaBlend(chip.color!, card);
      final avatarBackground = Color.alphaBlend(avatar.color!, card);
      final labelColor = tester.widget<Text>(find.text('Relay')).style!.color!;
      final mark = tester.widget<Icon>(find.byIcon(Icons.cell_tower)).color!;
      final dot = tester.widget<PulseDot>(find.byType(PulseDot)).color;
      final initials = tester.widget<Text>(find.text('AB')).style!.color!;
      final avatarMark = tester.widget<Icon>(find.byIcon(Icons.group)).color!;
      expect(meshContrastRatio(labelColor, chipBackground),
          greaterThanOrEqualTo(4.5));
      for (final color in [mark, dot]) {
        expect(meshContrastRatio(Color.alphaBlend(color, chipBackground),
            chipBackground), greaterThanOrEqualTo(3));
      }
      expect(meshContrastRatio(Color.alphaBlend(initials, avatarBackground),
          avatarBackground), greaterThanOrEqualTo(4.5));
      expect(meshContrastRatio(Color.alphaBlend(avatarMark, avatarBackground),
          avatarBackground), greaterThanOrEqualTo(3));
      expect(tester.getSize(find.byKey(avatarKey)), const Size(44, 44));
      expect(tester.widget<PulseDot>(find.byType(PulseDot)).animate, isFalse);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
