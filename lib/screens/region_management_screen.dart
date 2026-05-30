import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/l10n.dart';
import 'package:meshcore_open/storage/region_store.dart';
import 'package:provider/provider.dart';

Future<void> pushRegionManagementScreen(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (context) => const RegionManagementScreen(),
    ),
  );
}

class RegionManagementScreen extends StatefulWidget {
  const RegionManagementScreen({super.key});

  @override
  State<RegionManagementScreen> createState() => _RegionManagementScreenState();
}

class _RegionManagementScreenState extends State<RegionManagementScreen> {
  final RegionStore _regionStore = RegionStore();
  List<Region> _regions = [];

  String region = '';

  @override
  void initState() {
    super.initState();
    final connector = context.read<MeshCoreConnector>();
    _regionStore.setPublicKeyHex = connector.selfPublicKeyHex;
    _loadRegions();
  }

  void _loadRegions() {
    context.read<MeshCoreConnector>().loadChannelSettings();

    final regions = _regionStore.loadRegions();
    if (mounted) {
      setState(() {
        _regions = regions;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings_regionManagement_screenTitle),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: l10n.settings_regionAddRegion,
            icon: const Icon(Icons.add),
            onPressed: () => _showAddRegionDialog(context),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 88),
        itemCount: _regions.length,
        itemBuilder: (context, index) {
          final region = _regions[index];
          return _buildRegionTile(context, region);
        },
      ),
    );
  }

  void _showAddRegionDialog(BuildContext context) {
    final l10n = context.l10n;
    final controller = TextEditingController(text: region);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settings_regionName),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _handleAddRegion(controller.text, context),
          decoration: InputDecoration(
            hintText: l10n.settings_regionNameHint,
            border: const OutlineInputBorder(),
          ),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp("[a-z0-9-]")),
          ],
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => _handleAddRegion(controller.text, context),
            child: Text(l10n.common_add),
          ),
        ],
      ),
    );
  }

  void _handleAddRegion(Region region, BuildContext context) {
    Navigator.pop(context);
    _regionStore.addRegion(region);
    _loadRegions();
  }

  Widget _buildRegionTile(BuildContext context, Region region) {
    return Card(
      key: ValueKey(region),
      child: ListTile(
        dense: false,
        title: Text(region),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline),
          onPressed: () => _confirmDelete(context, region),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Region region) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.settings_deleteRegion),
        content: Text(context.l10n.settings_deleteRegionConfirm(region)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _regionStore.removeRegion(region);
              _loadRegions();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.l10n.settings_regionDeleted)),
              );
            },
            child: Text(
              context.l10n.common_delete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
