import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../services/app_settings_service.dart';

class IpfsImageLinksDialog extends StatefulWidget {
  const IpfsImageLinksDialog({super.key, required this.settingsService});

  final AppSettingsService settingsService;

  @override
  State<IpfsImageLinksDialog> createState() => _IpfsImageLinksDialogState();
}

class _IpfsImageLinksDialogState extends State<IpfsImageLinksDialog> {
  late final TextEditingController _publicController;
  late final TextEditingController _uploadGatewayController;
  late final TextEditingController _endpointController;
  late final TextEditingController _apiKeyController;
  final FocusNode _apiKeyFocus = FocusNode();
  late final String _currentApiKey;
  late final String _maskedApiKey;
  late String _selectedGateway;
  late String _selectedUploadProvider;
  bool _apiKeyChanged = false;
  bool _apiKeyObscured = true;

  @override
  void initState() {
    super.initState();
    final settings = widget.settingsService.settings;
    _publicController = TextEditingController(
      text: normalizeIpfsGateway(settings.publicIpfsGateway),
    );
    _uploadGatewayController = TextEditingController(
      text: normalizeIpfsGateway(settings.uploadIpfsGateway),
    );
    _endpointController = TextEditingController(
      text: settings.uploadIpfsEndpoint,
    );
    _currentApiKey = settings.uploadIpfsApiKey.trim();
    _maskedApiKey = _currentApiKey.isEmpty ? '' : _maskApiKey(_currentApiKey);
    _apiKeyController = TextEditingController(text: _maskedApiKey);
    _apiKeyFocus.addListener(_onApiKeyFocusChanged);
    _selectedGateway = _gatewayPreset(_publicController.text);
    _selectedUploadProvider = _uploadProvider(
      _uploadGatewayController.text,
      _endpointController.text,
      _currentApiKey,
    );
  }

  @override
  void dispose() {
    _publicController.dispose();
    _uploadGatewayController.dispose();
    _endpointController.dispose();
    _apiKeyController.dispose();
    _apiKeyFocus.dispose();
    super.dispose();
  }

  /// Swaps the masked key out while the field has focus (by tap, Tab or
  /// keyboard) so typing never appends to the mask, and puts it back if the
  /// user leaves without editing.
  void _onApiKeyFocusChanged() {
    if (_apiKeyChanged) return;
    _apiKeyController.text = _apiKeyFocus.hasFocus ? '' : _maskedApiKey;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.appSettings_ipfsImageLinks),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.appSettings_ipfsImageLinksDescription),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedGateway,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.appSettings_publicIpfsGateway,
              ),
              items: [
                DropdownMenuItem(
                  value: 'deactivated',
                  child: Text(l10n.appSettings_ipfsGatewayDeactivated),
                ),
                DropdownMenuItem(
                  value: 'ipfsio',
                  child: Text(l10n.appSettings_ipfsGatewayIpfsIo),
                ),
                DropdownMenuItem(
                  value: 'pinata',
                  child: Text(l10n.appSettings_ipfsGatewayPinata),
                ),
                DropdownMenuItem(
                  value: 'filebase',
                  child: Text(l10n.appSettings_ipfsGatewayFilebase),
                ),
                DropdownMenuItem(
                  value: 'custom',
                  child: Text(l10n.appSettings_ipfsGatewayCustom),
                ),
              ],
              onChanged: _selectGateway,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _publicController,
              key: const ValueKey('ipfs-public-gateway'),
              decoration: InputDecoration(
                labelText: l10n.appSettings_publicIpfsGateway,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) {
                if (_selectedGateway != 'custom') {
                  setState(() => _selectedGateway = 'custom');
                }
              },
            ),
            const Divider(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _selectedUploadProvider,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.appSettings_uploadIpfsProvider,
              ),
              items: [
                DropdownMenuItem(
                  value: 'pinata',
                  child: Text(l10n.appSettings_ipfsGatewayPinata),
                ),
                DropdownMenuItem(
                  value: 'filebase',
                  child: Text(l10n.appSettings_ipfsGatewayFilebase),
                ),
                DropdownMenuItem(
                  value: 'custom',
                  child: Text(l10n.appSettings_ipfsGatewayCustom),
                ),
                DropdownMenuItem(
                  value: 'deactivated',
                  child: Text(l10n.appSettings_ipfsGatewayDeactivated),
                ),
              ],
              onChanged: _selectUploadProvider,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _uploadGatewayController,
              key: const ValueKey('ipfs-upload-gateway'),
              decoration: InputDecoration(
                labelText: l10n.appSettings_uploadIpfsGateway,
                helperText: l10n.appSettings_uploadIpfsGatewaySubtitle,
                helperMaxLines: 3,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => _markCustomUploadProvider(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _endpointController,
              key: const ValueKey('ipfs-upload-endpoint'),
              decoration: InputDecoration(
                labelText: l10n.appSettings_uploadIpfsEndpoint,
                helperText: l10n.appSettings_uploadIpfsEndpointSubtitle,
                helperMaxLines: 3,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => _markCustomUploadProvider(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKeyController,
              key: const ValueKey('ipfs-upload-key'),
              focusNode: _apiKeyFocus,
              decoration: InputDecoration(
                labelText: l10n.appSettings_uploadIpfsApiKey,
                suffixIcon: IconButton(
                  tooltip: _apiKeyObscured
                      ? l10n.appSettings_showApiKey
                      : l10n.appSettings_hideApiKey,
                  icon: Icon(
                    _apiKeyObscured
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _apiKeyObscured = !_apiKeyObscured),
                ),
              ),
              autocorrect: false,
              enableSuggestions: false,
              obscureText: _apiKeyObscured,
              onChanged: (_) {
                _apiKeyChanged = true;
                _markCustomUploadProvider();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.common_cancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.common_save)),
      ],
    );
  }

  void _selectGateway(String? value) {
    if (value == null) return;
    setState(() {
      _selectedGateway = value;
      final preset = _gatewayValue(value);
      if (preset != null) _publicController.text = preset;
    });
  }

  void _selectUploadProvider(String? value) {
    if (value == null) return;
    setState(() {
      _selectedUploadProvider = value;
      final preset = _uploadPreset(value);
      if (preset != null) {
        _uploadGatewayController.text = preset.gateway;
        _endpointController.text = preset.endpoint;
        if (value == 'deactivated') _apiKeyController.clear();
      }
    });
  }

  void _markCustomUploadProvider() {
    if (_selectedUploadProvider != 'custom') {
      setState(() => _selectedUploadProvider = 'custom');
    }
  }

  Future<void> _save() async {
    final deactivated = _selectedUploadProvider == 'deactivated';
    final apiKey = _apiKeyController.text.trim();
    await widget.settingsService.setIpfsImageSettings(
      publicGateway: _publicController.text,
      uploadGateway: deactivated ? '' : _uploadGatewayController.text,
      uploadEndpoint: deactivated ? '' : _endpointController.text,
      uploadApiKey: deactivated
          ? ''
          : _apiKeyChanged && apiKey != _maskedApiKey
          ? apiKey
          : _currentApiKey,
    );
    if (mounted) Navigator.pop(context);
  }

  String _gatewayPreset(String value) {
    if (value.isEmpty) return 'deactivated';
    // Named presets identify their own host, independently of the default.
    if (value == 'https://ipfs.io/ipfs/' || value == 'https://ipfs.io/ipfs') {
      return 'ipfsio';
    }
    if (value == 'https://gateway.pinata.cloud/ipfs/' ||
        value == 'https://gateway.pinata.cloud/ipfs') {
      return 'pinata';
    }
    if (value == 'https://ipfs.filebase.io/ipfs/' ||
        value == 'https://ipfs.filebase.io/ipfs') {
      return 'filebase';
    }
    return 'custom';
  }

  String? _gatewayValue(String preset) {
    switch (preset) {
      case 'deactivated':
        return '';
      case 'ipfsio':
        return 'https://ipfs.io/ipfs/';
      case 'pinata':
        return 'https://gateway.pinata.cloud/ipfs/';
      case 'filebase':
        return 'https://ipfs.filebase.io/ipfs/';
      case 'custom':
        return 'http://127.0.0.1:8080/ipfs/';
      default:
        return null;
    }
  }

  String _uploadProvider(String gateway, String endpoint, String apiKey) {
    if (gateway.isEmpty && endpoint.isEmpty && apiKey.isEmpty) {
      return 'deactivated';
    }
    if (gateway == 'https://gateway.pinata.cloud/ipfs/' &&
        endpoint == 'https://api.pinata.cloud/pinning/pinFileToIPFS') {
      return 'pinata';
    }
    if (gateway == 'https://ipfs.filebase.io/ipfs/' &&
        endpoint == 'https://rpc.filebase.io/api/v0/add') {
      return 'filebase';
    }
    return 'custom';
  }

  ({String gateway, String endpoint})? _uploadPreset(String preset) {
    switch (preset) {
      case 'pinata':
        return (
          gateway: 'https://gateway.pinata.cloud/ipfs/',
          endpoint: 'https://api.pinata.cloud/pinning/pinFileToIPFS',
        );
      case 'filebase':
        return (
          gateway: 'https://ipfs.filebase.io/ipfs/',
          endpoint: 'https://rpc.filebase.io/api/v0/add',
        );
      case 'custom':
        return (
          gateway: 'http://127.0.0.1:8080/ipfs/',
          endpoint: 'http://127.0.0.1:5001/api/v0/add',
        );
      case 'deactivated':
        return (gateway: '', endpoint: '');
      default:
        return null;
    }
  }

  String _maskApiKey(String value) {
    if (value.length <= 8) return '********';
    return '${value.substring(0, 4)}...${value.substring(value.length - 4)}';
  }
}
