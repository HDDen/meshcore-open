import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../services/app_settings_service.dart';
import '../utils/platform_info.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../helpers/snack_bar_builder.dart';
import 'contacts_screen.dart';
import 'usb_screen.dart';

class TcpScreen extends StatefulWidget {
  const TcpScreen({super.key});

  @override
  State<TcpScreen> createState() => _TcpScreenState();
}

class _TcpScreenState extends State<TcpScreen> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final MeshCoreConnector _connector;
  late final AppSettingsService _settingsService;
  late final VoidCallback _connectionListener;
  bool _navigatedToContacts = false;

  @override
  void initState() {
    super.initState();
    _settingsService = context.read<AppSettingsService>();
    _hostController = TextEditingController(
      text: _settingsService.settings.tcpServerAddress,
    );
    _portController = TextEditingController(
      text: _settingsService.settings.tcpServerPort > 0
          ? _settingsService.settings.tcpServerPort.toString()
          : '',
    );
    _connector = context.read<MeshCoreConnector>();

    _connectionListener = () {
      if (!mounted) return;
      if (_connector.state == MeshCoreConnectionState.disconnected) {
        _navigatedToContacts = false;
      }
      if (_connector.state == MeshCoreConnectionState.connected &&
          _connector.isTcpTransportConnected &&
          !_navigatedToContacts) {
        _navigatedToContacts = true;
        unawaited(
          Future<void>.delayed(Duration.zero, _handleSuccessfulTcpConnection),
        );
      }
    };
    _connector.addListener(_connectionListener);
  }

  @override
  void dispose() {
    _connector.removeListener(_connectionListener);
    _hostController.dispose();
    _portController.dispose();
    if (!_navigatedToContacts &&
        _connector.activeTransport == MeshCoreTransportType.tcp &&
        _connector.state != MeshCoreConnectionState.disconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_connector.disconnect(manual: true));
      });
    }
    super.dispose();
  }

  Future<void> _handleSuccessfulTcpConnection() async {
    if (!mounted) return;
    final host = _hostController.text;
    final port = int.tryParse(_portController.text) ?? 0;
    await _settingsService.recordTcpConnection(host, port);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ContactsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: AdaptiveAppBarTitle(context.l10n.tcpScreenTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: Consumer2<MeshCoreConnector, AppSettingsService>(
          builder: (context, connector, settingsService, child) {
            final isConnecting =
                connector.state == MeshCoreConnectionState.connecting &&
                connector.activeTransport == MeshCoreTransportType.tcp;
            final isButtonDisabled =
                isConnecting ||
                connector.state == MeshCoreConnectionState.scanning;
            return Column(
              children: [
                _buildStatusBar(context, connector),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      TextField(
                        controller: _hostController,
                        decoration: InputDecoration(
                          labelText: context.l10n.tcpHostLabel,
                          hintText: context.l10n.tcpHostHint,
                          border: const OutlineInputBorder(),
                        ),
                        enabled: !isConnecting,
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _portController,
                        decoration: InputDecoration(
                          labelText: context.l10n.tcpPortLabel,
                          hintText: context.l10n.tcpPortHint,
                          border: const OutlineInputBorder(),
                        ),
                        enabled: !isConnecting,
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('tcp_connect_button'),
                        onPressed: isButtonDisabled ? null : _connectTcp,
                        icon: isConnecting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lan),
                        label: Text(
                          isConnecting
                              ? context.l10n.scanner_connecting
                              : context.l10n.common_connect,
                        ),
                      ),
                      if (settingsService
                          .settings
                          .tcpConnectionBookmarks
                          .isNotEmpty) ...[
                        const SizedBox(height: 24),
                        // Successful TCP endpoints are kept as quick-fill bookmarks.
                        _buildBookmarksBlock(
                          context,
                          settingsService.settings.tcpConnectionBookmarks,
                          enabled: !isConnecting,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (PlatformInfo.supportsUsbSerial)
                FloatingActionButton.extended(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const UsbScreen()),
                    );
                  },
                  heroTag: 'tcp_usb_action',
                  extendedPadding: const EdgeInsets.symmetric(horizontal: 12),
                  icon: const Icon(Icons.usb),
                  label: Text(context.l10n.connectionChoiceUsbLabel),
                ),
              if (PlatformInfo.supportsUsbSerial) const SizedBox(width: 12),
              FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context).maybePop();
                },
                heroTag: 'tcp_ble_action',
                extendedPadding: const EdgeInsets.symmetric(horizontal: 12),
                icon: const Icon(Icons.bluetooth),
                label: Text(context.l10n.connectionChoiceBluetoothLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarksBlock(
    BuildContext context,
    List<TcpConnectionBookmark> bookmarks, {
    required bool enabled,
  }) {
    final sortedBookmarks = List<TcpConnectionBookmark>.from(bookmarks)
      ..sort((a, b) => b.lastConnectedAt.compareTo(a.lastConnectedAt));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.l10n.tcpBookmarksLabel,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final bookmark in sortedBookmarks)
          Card(
            child: ListTile(
              enabled: enabled,
              leading: IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: enabled
                    ? () => _showBookmarkNameDialog(context, bookmark)
                    : null,
              ),
              title: _buildBookmarkTitle(context, bookmark),
              subtitle: _buildBookmarkEndpoint(context, bookmark),
              onTap: enabled ? () => _applyBookmark(bookmark) : null,
            ),
          ),
      ],
    );
  }

  Widget _buildBookmarkTitle(
    BuildContext context,
    TcpConnectionBookmark bookmark,
  ) {
    final name = bookmark.name.trim();
    final date = _formatBookmarkTimestamp(bookmark.lastConnectedAt);
    if (name.isEmpty) return Text(date);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(name),
        const SizedBox(height: 6),
        _buildBookmarkDivider(context),
        const SizedBox(height: 6),
        Text(date),
      ],
    );
  }

  Widget _buildStatusBar(BuildContext context, MeshCoreConnector connector) {
    final l10n = context.l10n;
    String statusText;
    Color statusColor;

    if (connector.isTcpTransportConnected) {
      statusText = l10n.scanner_connectedTo(
        connector.activeTcpEndpoint ?? 'TCP',
      );
      statusColor = Colors.green;
    } else if (connector.state == MeshCoreConnectionState.connecting &&
        connector.activeTransport == MeshCoreTransportType.tcp) {
      statusText = l10n.tcpStatus_connectingTo(
        '${_hostController.text}:${_portController.text}',
      );
      statusColor = Colors.orange;
    } else if (connector.state == MeshCoreConnectionState.disconnecting &&
        connector.activeTransport == MeshCoreTransportType.tcp) {
      statusText = l10n.scanner_disconnecting;
      statusColor = Colors.orange;
    } else {
      statusText = l10n.tcpStatus_notConnected;
      statusColor = Colors.grey;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: statusColor.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarkEndpoint(
    BuildContext context,
    TcpConnectionBookmark bookmark,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        _buildBookmarkDivider(context),
        const SizedBox(height: 6),
        Text('${bookmark.host}:${bookmark.port}'),
      ],
    );
  }

  Widget _buildBookmarkDivider(BuildContext context) {
    final color = Theme.of(context).dividerColor.withValues(alpha: 0.45);
    return Divider(height: 1, color: color);
  }

  Future<void> _showBookmarkNameDialog(
    BuildContext context,
    TcpConnectionBookmark bookmark,
  ) async {
    final settingsService = context.read<AppSettingsService>();
    final title = context.l10n.tcpBookmarksSetName;
    final cancelLabel = context.l10n.common_cancel;
    final saveLabel = context.l10n.common_save;
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final controller = TextEditingController(text: bookmark.name);
    final updatedName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: titleStyle),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(saveLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updatedName == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await settingsService.setTcpConnectionBookmarkName(bookmark, updatedName);
  }

  void _applyBookmark(TcpConnectionBookmark bookmark) {
    _hostController.text = bookmark.host;
    _portController.text = bookmark.port.toString();
    _hostController.selection = TextSelection.collapsed(
      offset: _hostController.text.length,
    );
    _portController.selection = TextSelection.collapsed(
      offset: _portController.text.length,
    );
  }

  String _formatBookmarkTimestamp(DateTime value) {
    // The requested format is day-month-year hour:minute:second.
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$day-$month-${value.year} $hour:$minute:$second';
  }

  Future<void> _connectTcp() async {
    if (_connector.state == MeshCoreConnectionState.connecting ||
        _connector.state == MeshCoreConnectionState.connected ||
        _connector.state == MeshCoreConnectionState.disconnecting) {
      return;
    }

    final host = _hostController.text.trim();
    final parsedPort = int.tryParse(_portController.text.trim());
    if (host.isEmpty) {
      _showError(context.l10n.tcpErrorHostRequired);
      return;
    }
    if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
      _showError(context.l10n.tcpErrorPortInvalid);
      return;
    }

    try {
      await _connector.connectTcp(host: host, port: parsedPort);
    } catch (error) {
      if (!mounted) return;
      _showError(_friendlyErrorMessage(error));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(message),
      backgroundColor: Colors.red,
    );
  }

  String _friendlyErrorMessage(Object error) {
    if (error is UnsupportedError) {
      return context.l10n.tcpErrorUnsupported;
    }
    if (error is TimeoutException) {
      return context.l10n.tcpErrorTimedOut;
    }
    if (error is StateError) {
      return context.l10n.tcpConnectionFailed(error.message);
    }
    if (error is ArgumentError) {
      return context.l10n.tcpConnectionFailed(
        error.message?.toString() ?? error.toString(),
      );
    }
    return context.l10n.tcpConnectionFailed(error.toString());
  }
}
