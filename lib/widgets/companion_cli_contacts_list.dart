import 'package:flutter/material.dart';

import '../connector/meshcore_connector.dart';
import 'companion_cli_tile.dart';

/// CLI — первый прокручиваемый sliver; индексы/ключи обычных контактов не сдвигаются.
class CompanionCliContactsList extends StatelessWidget {
  const CompanionCliContactsList({super.key, required this.connector,
    required this.sliver, required this.showCli}) : _placeholder = false;

  CompanionCliContactsList.placeholder({super.key, required this.connector,
    required Widget child, this.showCli = true})
    : sliver = SliverFillRemaining(hasScrollBody: false, child: child),
      _placeholder = true;

  final MeshCoreConnector connector;
  final Widget sliver;
  final bool showCli;
  final bool _placeholder;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: _placeholder ? const AlwaysScrollableScrollPhysics() : null,
    slivers: [
      if (showCli) SliverToBoxAdapter(child: CompanionCliTile(
        connector: connector, compact: true,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 4))),
      sliver,
      if (!_placeholder) const SliverToBoxAdapter(child: SizedBox(height: 88)),
    ],
  );
}
