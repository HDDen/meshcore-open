import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../services/repeater_command_service.dart';
import '../services/storage_service.dart';
import '../widgets/path_management_dialog.dart';
import '../helpers/snack_bar_builder.dart';

class RepeaterSettingsScreen extends StatefulWidget {
  final Contact repeater;
  final String password;

  const RepeaterSettingsScreen({
    super.key,
    required this.repeater,
    required this.password,
  });

  @override
  State<RepeaterSettingsScreen> createState() => _RepeaterSettingsScreenState();
}

enum _SettingField {
  name,
  radio,
  txPower,
  rxGain,
  lat,
  lon,
  repeat,
  allowReadOnly,
  multiAcks,
  loopDetect,
  dutyCycle,
  ownerInfo,
  floodMax,
  advertInterval,
  floodAdvertInterval,
  pathHashMode,
  txDelay,
  directTxDelay,
  intThresh,
  agcResetInterval,
}

enum _SaveOutcome { ok, rebootNeeded, error }

// Firmware reply taxonomy for `set ...` / `password ...` commands
// (see MeshCore CommonCLI.cpp): success replies always start with "OK"
// (any case) or "password now:"; reboot-required successes contain the word
// "reboot" (e.g. "OK - reboot to apply", "OK, reboot to apply! New pubkey:...");
// some replies are parenthesized like "(OK - stats reset)". Anything else
// (Error/ERR/ERROR/unknown/can't/...) is a failure.
_SaveOutcome _classifySaveResponse(String response) {
  var s = response.trim();
  if (s.isEmpty) return _SaveOutcome.error;
  if (s.startsWith('(')) s = s.substring(1);
  final lower = s.toLowerCase();
  if (lower.startsWith('ok') || lower.startsWith('password now')) {
    return lower.contains('reboot')
        ? _SaveOutcome.rebootNeeded
        : _SaveOutcome.ok;
  }
  return _SaveOutcome.error;
}

String _shortCommandLabel(String command) {
  final firstSpace = command.indexOf(' ');
  if (firstSpace == -1) return command;
  if (command.startsWith('set ')) {
    final rest = command.substring(4);
    final nextSpace = rest.indexOf(' ');
    return nextSpace == -1 ? rest : rest.substring(0, nextSpace);
  }
  return command.substring(0, firstSpace);
}

class _RepeaterSettingsScreenState extends State<RepeaterSettingsScreen> {
  final StorageService _storage = StorageService();

  bool _isLoading = false;
  bool _hasChanges = false;
  final Set<_SettingField> _dirtyFields = {};
  bool _refreshingBasic = false;
  bool _refreshingRadio = false;
  bool _refreshingTxPower = false;
  bool _refreshingRxGain = false;
  bool _refreshingRepeat = false;
  bool _refreshingAllowReadOnly = false;
  bool _refreshingMultiAcks = false;
  bool _refreshingOwnerInfo = false;
  bool _refreshingLat = false;
  bool _refreshingLon = false;
  bool _refreshingLoopDetect = false;
  bool _refreshingDutyCycle = false;
  bool _refreshingAdvertInterval = false;
  bool _refreshingFloodAdvertInterval = false;
  bool _refreshingFloodMax = false;
  bool _refreshingPathHashMode = false;
  bool _refreshingTxDelay = false;
  bool _refreshingDirectTxDelay = false;
  bool _refreshingIntThresh = false;
  bool _refreshingAgcResetInterval = false;
  bool _runningAction = false;
  StreamSubscription<Uint8List>? _frameSubscription;
  RepeaterCommandService? _commandService;

  // Basic settings
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _guestPasswordController =
      TextEditingController();

  // Radio settings
  final TextEditingController _freqController = TextEditingController();
  final TextEditingController _txPowerController = TextEditingController();
  int? _bandwidth;
  int? _spreadingFactor;
  int? _codingRate;

  // Location settings
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();

  // Feature toggles
  bool _repeatEnabled = true;
  bool _allowReadOnly = true;
  bool _multiAcks = false;
  bool _rxGainBoosted = false;
  bool _autoClockSyncAfterLogin = false;

  // Advertisement settings
  bool _advertEnable = true;
  int _advertInterval = 120; // minutes/2
  bool _floodAdvertEnable = true;
  int _floodAdvertInterval = 12; // hours
  int _floodMax = 64; // 0-64 hops

  // Network health
  String _loopDetect = 'off'; // off|minimal|moderate|strict
  int _dutyCycle = 50; // 1-100

  // Operator info
  final TextEditingController _ownerInfoController = TextEditingController();

  // Advanced
  int _pathHashMode = 0; // 0-2
  final TextEditingController _txDelayController = TextEditingController();
  final TextEditingController _directTxDelayController =
      TextEditingController();
  final TextEditingController _intThreshController = TextEditingController();
  int _agcResetInterval = 0; // seconds, multiple of 4, 0 disabled

  static const List<String> _loopDetectOptions = [
    'off',
    'minimal',
    'moderate',
    'strict',
  ];

  final List<int> _bandwidthOptions = [
    7800,
    10400,
    15600,
    20800,
    31250,
    41700,
    62500,
    125000,
    250000,
    500000,
  ];
  final List<int> _spreadingFactorOptions = [5, 6, 7, 8, 9, 10, 11, 12];
  final List<int> _codingRateOptions = [5, 6, 7, 8];

  @override
  void initState() {
    super.initState();
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _commandService = RepeaterCommandService(connector);
    _setupMessageListener();
    _loadSettings();
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _commandService?.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _guestPasswordController.dispose();
    _freqController.dispose();
    _txPowerController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _ownerInfoController.dispose();
    _txDelayController.dispose();
    _directTxDelayController.dispose();
    _intThreshController.dispose();
    super.dispose();
  }

  void _setupMessageListener() {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    // Listen for incoming text messages from the repeater
    _frameSubscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;

      // Check if it's a text message response
      if (frame[0] == respCodeContactMsgRecv ||
          frame[0] == respCodeContactMsgRecvV3) {
        _handleTextMessageResponse(frame);
      }
    });
  }

  void _handleTextMessageResponse(Uint8List frame) {
    final parsed = parseContactMessageText(frame);
    if (parsed == null) return;
    if (!_matchesRepeaterPrefix(parsed.senderPrefix)) return;

    // Notify command service of response (for retry handling)
    _commandService?.handleResponse(widget.repeater, parsed.text);
  }

  int _resolveRepeaterIndex = -1;

  Contact _resolveRepeater(MeshCoreConnector connector) {
    if (_resolveRepeaterIndex >= 0 &&
        _resolveRepeaterIndex < connector.contacts.length &&
        connector.contacts[_resolveRepeaterIndex].publicKeyHex ==
            widget.repeater.publicKeyHex) {
      return connector.contacts[_resolveRepeaterIndex];
    }
    _resolveRepeaterIndex = connector.contacts.indexWhere(
      (c) => c.publicKeyHex == widget.repeater.publicKeyHex,
    );
    if (_resolveRepeaterIndex == -1) {
      return widget.repeater;
    }
    return connector.contacts[_resolveRepeaterIndex];
  }

  bool _matchesRepeaterPrefix(Uint8List prefix) {
    final target = widget.repeater.publicKey;
    if (target.length < 6 || prefix.length < 6) return false;
    for (int i = 0; i < 6; i++) {
      if (prefix[i] != target[i]) return false;
    }
    return true;
  }

  /// Apply a single `get <key>` response value to the relevant UI state.
  /// Caller is responsible for invoking this inside setState.
  /// Unparseable values are ignored (current state is preserved).
  void _applyGetValue(String key, String value) {
    switch (key) {
      case 'name':
        _nameController.text = value;
        break;
      case 'radio':
        _applyRadioValue(value);
        break;
      case 'tx':
        final dbm = int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), ''));
        if (dbm != null && dbm >= 1 && dbm <= 30) {
          _txPowerController.text = dbm.toString();
        }
        break;
      case 'lat':
        _latController.text = value;
        break;
      case 'lon':
        _lonController.text = value;
        break;
      case 'repeat':
        _repeatEnabled = _parseOnOff(value);
        break;
      case 'allow.read.only':
        _allowReadOnly = _parseOnOff(value);
        break;
      case 'advert.interval':
        final v = int.tryParse(value.trim());
        if (v != null && v >= 0) {
          _advertInterval = v;
          _advertEnable = v > 0;
        }
        break;
      case 'flood.advert.interval':
        final v = int.tryParse(value.trim());
        if (v != null && v >= 0) {
          _floodAdvertInterval = v;
          _floodAdvertEnable = v > 0;
        }
        break;
      case 'radio.rxgain':
        _rxGainBoosted = _parseOnOff(value);
        break;
      case 'multi.acks':
        // Firmware reply is "0" or "1".
        _multiAcks = _parseOnOff(value);
        break;
      case 'loop.detect':
        final lower = value.trim().toLowerCase();
        if (_loopDetectOptions.contains(lower)) _loopDetect = lower;
        break;
      case 'dutycycle':
        // Reply is "<int>.<int>%" e.g. "50.0%"; first number is the percent.
        final pct = double.tryParse(
          value.replaceAll('%', '').split('.').first.trim(),
        );
        if (pct != null) _dutyCycle = pct.toInt().clamp(1, 100);
        break;
      case 'owner.info':
        // Firmware translates internal newlines back to '|' on the wire.
        _ownerInfoController.text = value.replaceAll('|', '\n');
        break;
      case 'flood.max':
        final v = int.tryParse(value.trim());
        if (v != null && v >= 0 && v <= 64) _floodMax = v;
        break;
      case 'path.hash.mode':
        final v = int.tryParse(value.trim());
        if (v != null && v >= 0 && v <= 2) _pathHashMode = v;
        break;
      case 'txdelay':
        if (double.tryParse(value.trim()) != null) {
          _txDelayController.text = value.trim();
        }
        break;
      case 'direct.txdelay':
        if (double.tryParse(value.trim()) != null) {
          _directTxDelayController.text = value.trim();
        }
        break;
      case 'int.thresh':
        if (int.tryParse(value.trim()) != null) {
          _intThreshController.text = value.trim();
        }
        break;
      case 'agc.reset.interval':
        final v = int.tryParse(value.trim());
        if (v != null && v >= 0) _agcResetInterval = v;
        break;
    }
  }

  /// Parse the firmware "freq,bw,sf,cr" radio reply (e.g. "908.205017,62.5,10,7").
  void _applyRadioValue(String radioStr) {
    final parts = radioStr.split(',');
    if (parts.isEmpty) return;
    final freqText = parts[0].trim();
    if (freqText.isNotEmpty && double.tryParse(freqText) != null) {
      _freqController.text = freqText;
    }
    if (parts.length > 1) {
      final bw = double.tryParse(parts[1].trim());
      if (bw != null) {
        _bandwidth = (bw * 1000).toInt();
        if (!_bandwidthOptions.contains(_bandwidth)) {
          _bandwidthOptions.add(_bandwidth!);
          _bandwidthOptions.sort();
        }
      }
    }
    if (parts.length > 2) {
      _spreadingFactor = int.tryParse(parts[2].trim()) ?? _spreadingFactor;
    }
    if (parts.length > 3) {
      _codingRate = int.tryParse(parts[3].trim()) ?? _codingRate;
    }
  }

  bool _parseOnOff(String value) {
    final lower = value.trim().toLowerCase();
    return lower == 'on' ||
        lower == 'true' ||
        lower == '1' ||
        lower == 'enabled';
  }

  String _formatBandwidthLabel(int bandwidthHz) {
    final bandwidthKHz = bandwidthHz / 1000;
    var text = bandwidthKHz.toStringAsFixed(2);
    text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return '$text kHz';
  }

  /// Decode a `get <key>` response and apply it to local state.
  /// Returns true if a value was applied.
  ///
  /// Response/command pairing is guaranteed by the prefix-matching layer in
  /// RepeaterCommandService (firmware echoes the `XX|` token from MyMesh.cpp),
  /// so no shape-based validation is needed here — `tryParse` handles any
  /// malformed value by leaving state untouched.
  bool _handleGetResponse(String command, String response) {
    final normalized = command.trim().toLowerCase();
    if (!normalized.startsWith('get ')) return false;
    final key = normalized.substring(4).trim();
    final value = _extractGetValue(response);
    if (value == null) return false;
    setState(() => _applyGetValue(key, value));
    return true;
  }

  /// Firmware GET replies are always `> <value>` (CommonCLI.cpp `sprintf(reply, "> %s", ...)`).
  /// Returns the first such value, trimmed; null if none found.
  String? _extractGetValue(String response) {
    for (final line in response.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('>')) {
        final value = trimmed.substring(1).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Future<void> _refreshSection({
    required String label,
    required List<String> commands,
    required ValueSetter<bool> setRefreshing,
  }) async {
    if (_commandService == null) return;
    final l10n = context.l10n;

    setState(() => setRefreshing(true));

    var successCount = 0;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);
    for (final command in commands) {
      try {
        final response = await _commandService!.sendCommand(
          repeater,
          command,
          retries: 1,
        );
        if (_handleGetResponse(command, response)) successCount += 1;
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('Error fetching $command: $e');
      }
    }

    if (mounted) {
      showDismissibleSnackBar(
        context,
        content: Text(
          successCount > 0
              ? l10n.repeater_refreshed(label)
              : l10n.repeater_errorRefreshing(label),
        ),
        backgroundColor: successCount > 0 ? Colors.green : Colors.red,
      );
      setState(() => setRefreshing(false));
    }
  }

  Future<void> _refreshBasicSettings() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_basicSettings,
      commands: const ['get name'],
      setRefreshing: (value) => _refreshingBasic = value,
    );
  }

  Future<void> _refreshRadioSettings() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_radioSettings,
      commands: const ['get radio'],
      setRefreshing: (value) => _refreshingRadio = value,
    );
  }

  Future<void> _refreshTxPower() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_txPower,
      commands: const ['get tx'],
      setRefreshing: (value) => _refreshingTxPower = value,
    );
  }

  Future<void> _refreshRepeat() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_packetForwarding,
      commands: const ['get repeat'],
      setRefreshing: (value) => _refreshingRepeat = value,
    );
  }

  Future<void> _refreshAllowReadOnly() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_guestAccess,
      commands: const ['get allow.read.only'],
      setRefreshing: (value) => _refreshingAllowReadOnly = value,
    );
  }

  Future<void> _refreshRxGain() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_rxGain,
      commands: const ['get radio.rxgain'],
      setRefreshing: (value) => _refreshingRxGain = value,
    );
  }

  Future<void> _refreshMultiAcks() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_multiAcks,
      commands: const ['get multi.acks'],
      setRefreshing: (value) => _refreshingMultiAcks = value,
    );
  }

  Future<void> _refreshOwnerInfo() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_ownerInfo,
      commands: const ['get owner.info'],
      setRefreshing: (value) => _refreshingOwnerInfo = value,
    );
  }

  Future<void> _refreshLat() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_latitude,
      commands: const ['get lat'],
      setRefreshing: (value) => _refreshingLat = value,
    );
  }

  Future<void> _refreshLon() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_longitude,
      commands: const ['get lon'],
      setRefreshing: (value) => _refreshingLon = value,
    );
  }

  Future<void> _refreshLoopDetect() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_loopDetect,
      commands: const ['get loop.detect'],
      setRefreshing: (value) => _refreshingLoopDetect = value,
    );
  }

  Future<void> _refreshDutyCycle() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_dutyCycle,
      commands: const ['get dutycycle'],
      setRefreshing: (value) => _refreshingDutyCycle = value,
    );
  }

  Future<void> _refreshAdvertInterval() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_localAdvertInterval,
      commands: const ['get advert.interval'],
      setRefreshing: (value) => _refreshingAdvertInterval = value,
    );
  }

  Future<void> _refreshFloodAdvertInterval() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_floodAdvertInterval,
      commands: const ['get flood.advert.interval'],
      setRefreshing: (value) => _refreshingFloodAdvertInterval = value,
    );
  }

  Future<void> _refreshFloodMax() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_floodMax,
      commands: const ['get flood.max'],
      setRefreshing: (value) => _refreshingFloodMax = value,
    );
  }

  Future<void> _refreshPathHashMode() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_pathHashMode,
      commands: const ['get path.hash.mode'],
      setRefreshing: (value) => _refreshingPathHashMode = value,
    );
  }

  Future<void> _refreshTxDelay() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_txDelay,
      commands: const ['get txdelay'],
      setRefreshing: (value) => _refreshingTxDelay = value,
    );
  }

  Future<void> _refreshDirectTxDelay() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_directTxDelay,
      commands: const ['get direct.txdelay'],
      setRefreshing: (value) => _refreshingDirectTxDelay = value,
    );
  }

  Future<void> _refreshIntThresh() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_intThresh,
      commands: const ['get int.thresh'],
      setRefreshing: (value) => _refreshingIntThresh = value,
    );
  }

  Future<void> _refreshAgcResetInterval() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_agcResetInterval,
      commands: const ['get agc.reset.interval'],
      setRefreshing: (value) => _refreshingAgcResetInterval = value,
    );
  }

  /// Send a one-shot CLI action (advert / clock sync / etc.) and surface the
  /// firmware's reply via snackbar. Not part of the dirty-field save flow.
  Future<void> _runAction(String command, String label) async {
    if (_commandService == null) return;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);
    final l10n = context.l10n;
    setState(() => _runningAction = true);
    try {
      final response = await _commandService!.sendCommand(
        repeater,
        command,
        retries: 1,
      );
      if (!mounted) return;
      final outcome = _classifySaveResponse(response);
      showDismissibleSnackBar(
        context,
        content: Text(
          outcome == _SaveOutcome.error
              ? l10n.repeater_actionFailed(label, response.trim())
              : l10n.repeater_actionSucceeded(label),
        ),
        backgroundColor: outcome == _SaveOutcome.error
            ? Colors.red
            : Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(l10n.repeater_actionFailed(label, e.toString())),
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _loadSettings() async {
    // Just populate with current repeater data on initial load
    // User must click sync button to fetch from device
    setState(() {
      _nameController.text = widget.repeater.name;

      if (widget.repeater.hasLocation) {
        _latController.text = widget.repeater.latitude?.toString() ?? '';
        _lonController.text = widget.repeater.longitude?.toString() ?? '';
      }
    });

    final autoClockSync = await _storage
        .getRepeaterAutoClockSyncAfterLoginEnabled(
          widget.repeater.publicKeyHex,
        );
    if (!mounted) return;
    setState(() {
      _autoClockSyncAfterLogin = autoClockSync;
    });
  }

  Future<void> _saveSettings() async {
    if (_commandService == null) return;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);

    setState(() {
      _isLoading = true;
    });

    try {
      // Each pending command remembers the dirty-field it came from (null for
      // password commands, which always re-send when text is present). On
      // failure we keep that field in `_dirtyFields` so the Save button stays
      // available and the user can retry.
      final pending = <({_SettingField? field, String command})>[];

      if (_dirtyFields.contains(_SettingField.name) &&
          _nameController.text.isNotEmpty) {
        pending.add((
          field: _SettingField.name,
          command: 'set name ${_nameController.text}',
        ));
      }

      // Passwords are write-only; send whenever a value was typed.
      if (_passwordController.text.isNotEmpty) {
        pending.add((
          field: null,
          command: 'password ${_passwordController.text}',
        ));
      }
      if (_guestPasswordController.text.isNotEmpty) {
        pending.add((
          field: null,
          command: 'set guest.password ${_guestPasswordController.text}',
        ));
      }

      // Radio parameters are bundled in a single command.
      if (_dirtyFields.contains(_SettingField.radio) &&
          _freqController.text.isNotEmpty &&
          _bandwidth != null &&
          _spreadingFactor != null &&
          _codingRate != null) {
        final freqText = _freqController.text.trim();
        if (double.tryParse(freqText) != null) {
          final bwKHz = _bandwidth! / 1000;
          pending.add((
            field: _SettingField.radio,
            command:
                'set radio $freqText,$bwKHz,$_spreadingFactor,$_codingRate',
          ));
        }
      }

      if (_dirtyFields.contains(_SettingField.txPower) &&
          _txPowerController.text.isNotEmpty) {
        final dbm = int.tryParse(_txPowerController.text.trim());
        if (dbm != null) {
          pending.add((field: _SettingField.txPower, command: 'set tx $dbm'));
        }
      }

      if (_dirtyFields.contains(_SettingField.lat) &&
          _latController.text.isNotEmpty) {
        pending.add((
          field: _SettingField.lat,
          command: 'set lat ${_latController.text}',
        ));
      }
      if (_dirtyFields.contains(_SettingField.lon) &&
          _lonController.text.isNotEmpty) {
        pending.add((
          field: _SettingField.lon,
          command: 'set lon ${_lonController.text}',
        ));
      }

      if (_dirtyFields.contains(_SettingField.repeat)) {
        pending.add((
          field: _SettingField.repeat,
          command: 'set repeat ${_repeatEnabled ? "on" : "off"}',
        ));
      }
      if (_dirtyFields.contains(_SettingField.allowReadOnly)) {
        pending.add((
          field: _SettingField.allowReadOnly,
          command: 'set allow.read.only ${_allowReadOnly ? "on" : "off"}',
        ));
      }

      if (_dirtyFields.contains(_SettingField.advertInterval)) {
        pending.add((
          field: _SettingField.advertInterval,
          command: 'set advert.interval $_advertInterval',
        ));
      }
      if (_dirtyFields.contains(_SettingField.floodAdvertInterval)) {
        pending.add((
          field: _SettingField.floodAdvertInterval,
          command: 'set flood.advert.interval $_floodAdvertInterval',
        ));
      }
      if (_dirtyFields.contains(_SettingField.floodMax)) {
        pending.add((
          field: _SettingField.floodMax,
          command: 'set flood.max $_floodMax',
        ));
      }

      if (_dirtyFields.contains(_SettingField.rxGain)) {
        pending.add((
          field: _SettingField.rxGain,
          command: 'set radio.rxgain ${_rxGainBoosted ? "on" : "off"}',
        ));
      }
      if (_dirtyFields.contains(_SettingField.multiAcks)) {
        pending.add((
          field: _SettingField.multiAcks,
          command: 'set multi.acks ${_multiAcks ? 1 : 0}',
        ));
      }
      if (_dirtyFields.contains(_SettingField.loopDetect)) {
        pending.add((
          field: _SettingField.loopDetect,
          command: 'set loop.detect $_loopDetect',
        ));
      }
      if (_dirtyFields.contains(_SettingField.dutyCycle)) {
        pending.add((
          field: _SettingField.dutyCycle,
          command: 'set dutycycle $_dutyCycle',
        ));
      }
      if (_dirtyFields.contains(_SettingField.ownerInfo)) {
        // Firmware splits on '|', treating it as newline.
        final encoded = _ownerInfoController.text.replaceAll('\n', '|');
        pending.add((
          field: _SettingField.ownerInfo,
          command: 'set owner.info $encoded',
        ));
      }
      if (_dirtyFields.contains(_SettingField.pathHashMode)) {
        pending.add((
          field: _SettingField.pathHashMode,
          command: 'set path.hash.mode $_pathHashMode',
        ));
      }
      if (_dirtyFields.contains(_SettingField.txDelay) &&
          _txDelayController.text.isNotEmpty) {
        final v = double.tryParse(_txDelayController.text.trim());
        if (v != null) {
          pending.add((
            field: _SettingField.txDelay,
            command: 'set txdelay $v',
          ));
        }
      }
      if (_dirtyFields.contains(_SettingField.directTxDelay) &&
          _directTxDelayController.text.isNotEmpty) {
        final v = double.tryParse(_directTxDelayController.text.trim());
        if (v != null) {
          pending.add((
            field: _SettingField.directTxDelay,
            command: 'set direct.txdelay $v',
          ));
        }
      }
      if (_dirtyFields.contains(_SettingField.intThresh) &&
          _intThreshController.text.isNotEmpty) {
        final v = int.tryParse(_intThreshController.text.trim());
        if (v != null) {
          pending.add((
            field: _SettingField.intThresh,
            command: 'set int.thresh $v',
          ));
        }
      }
      if (_dirtyFields.contains(_SettingField.agcResetInterval)) {
        pending.add((
          field: _SettingField.agcResetInterval,
          command: 'set agc.reset.interval $_agcResetInterval',
        ));
      }

      final failures = <String>[];
      final retainDirty = <_SettingField>{};
      var passwordsFailed = false;
      var rebootNeeded = false;
      for (final entry in pending) {
        var failed = false;
        try {
          final response = await _commandService!.sendCommand(
            repeater,
            entry.command,
            retries: 1,
          );
          final outcome = _classifySaveResponse(response);
          if (outcome == _SaveOutcome.error) {
            failures.add(
              '${_shortCommandLabel(entry.command)}: ${response.trim()}',
            );
            failed = true;
          } else if (outcome == _SaveOutcome.rebootNeeded) {
            rebootNeeded = true;
          }
        } catch (e) {
          failures.add('${_shortCommandLabel(entry.command)}: ${e.toString()}');
          failed = true;
        }
        if (failed) {
          if (entry.field != null) {
            retainDirty.add(entry.field!);
          } else {
            passwordsFailed = true;
          }
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Only clear password fields if every password command succeeded —
      // otherwise the user keeps their typed value to retry.
      if (!passwordsFailed) {
        _passwordController.clear();
        _guestPasswordController.clear();
      }
      setState(() {
        _isLoading = false;
        _dirtyFields
          ..clear()
          ..addAll(retainDirty);
        _hasChanges = _dirtyFields.isNotEmpty || passwordsFailed;
      });

      if (mounted) {
        final l10n = context.l10n;
        if (failures.isEmpty && rebootNeeded) {
          showDismissibleSnackBar(
            context,
            content: Text(l10n.repeater_settingsSavedRebootNeeded),
            backgroundColor: Colors.orange,
          );
        } else if (failures.isEmpty) {
          showDismissibleSnackBar(
            context,
            content: Text(l10n.repeater_settingsSaved),
            backgroundColor: Colors.green,
          );
        } else {
          showDismissibleSnackBar(
            context,
            content: Text(
              l10n.repeater_settingsPartialFailure(failures.join('; ')),
            ),
            backgroundColor: Colors.red,
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(
            context.l10n.repeater_errorSavingSettings(e.toString()),
          ),
          backgroundColor: Colors.red,
        );
      }
    }
  }

  void _markChanged(_SettingField field) {
    _dirtyFields.add(field);
    _flagHasChanges();
  }

  void _flagHasChanges() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? tooltip,
    bool isRefreshing = false,
    VoidCallback? onRefresh,
  }) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).textTheme.headlineSmall?.color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        if (onRefresh != null) ...[
          const Spacer(),
          IconButton(
            icon: isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: isRefreshing ? null : onRefresh,
            tooltip: tooltip,
          ),
        ],
      ],
    );
  }

  Widget _buildInlineRefreshButton({
    required bool isRefreshing,
    required VoidCallback onRefresh,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: IconButton(
        icon: isRefreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 20),
        onPressed: isRefreshing ? null : onRefresh,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connector = context.watch<MeshCoreConnector>();
    final repeater = _resolveRepeater(connector);
    final isFloodMode = repeater.pathOverride == -1;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.repeater_settingsTitle),
            Text(
              repeater.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(isFloodMode ? Icons.waves : Icons.route),
            tooltip: l10n.repeater_routingMode,
            onSelected: (mode) async {
              if (mode == 'flood') {
                await connector.setPathOverride(repeater, pathLen: -1);
              } else {
                await connector.setPathOverride(repeater, pathLen: null);
              }
              if (mounted) {
                setState(() {});
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'auto',
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_mode,
                      size: 20,
                      color: !isFloodMode
                          ? Theme.of(context).primaryColor
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.repeater_autoUseSavedPath,
                      style: TextStyle(
                        fontWeight: !isFloodMode
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'flood',
                child: Row(
                  children: [
                    Icon(
                      Icons.waves,
                      size: 20,
                      color: isFloodMode
                          ? Theme.of(context).primaryColor
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.repeater_forceFloodMode,
                      style: TextStyle(
                        fontWeight: isFloodMode
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.timeline),
            tooltip: l10n.repeater_pathManagement,
            onPressed: () =>
                PathManagementDialog.show(context, contact: repeater),
          ),
          if (_hasChanges)
            TextButton.icon(
              onPressed: _isLoading ? null : _saveSettings,
              icon: const Icon(Icons.save),
              label: Text(l10n.common_save),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isLoading && _nameController.text.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildBasicSettingsCard(),
                  const SizedBox(height: 16),
                  _buildRadioSettingsCard(),
                  const SizedBox(height: 16),
                  _buildLocationSettingsCard(),
                  const SizedBox(height: 16),
                  _buildFeatureTogglesCard(),
                  const SizedBox(height: 16),
                  _buildNetworkHealthCard(),
                  const SizedBox(height: 16),
                  _buildAdvertisementSettingsCard(),
                  const SizedBox(height: 16),
                  _buildOwnerInfoCard(),
                  const SizedBox(height: 16),
                  _buildActionsCard(),
                  const SizedBox(height: 16),
                  _buildAdvancedCard(),
                  const SizedBox(height: 32),
                  _buildDangerZoneCard(),
                ],
              ),
      ),
    );
  }

  Widget _buildBasicSettingsCard() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.settings,
              title: l10n.repeater_basicSettings,
              tooltip: l10n.repeater_refreshBasicSettings,
              isRefreshing: _refreshingBasic,
              onRefresh: _refreshBasicSettings,
            ),
            const Divider(),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: l10n.repeater_repeaterName,
                helperText: l10n.repeater_repeaterNameHelper,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _markChanged(_SettingField.name),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: l10n.repeater_adminPassword,
                helperText: l10n.repeater_adminPasswordHelper,
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
              onChanged: (_) => _flagHasChanges(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _guestPasswordController,
              decoration: InputDecoration(
                labelText: l10n.repeater_guestPassword,
                helperText: l10n.repeater_guestPasswordHelper,
                border: const OutlineInputBorder(),
              ),
              obscureText: true,
              onChanged: (_) => _flagHasChanges(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioSettingsCard() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.radio,
              title: l10n.repeater_radioSettings,
              tooltip: l10n.repeater_refreshRadioSettings,
              isRefreshing: _refreshingRadio,
              onRefresh: _refreshRadioSettings,
            ),
            const Divider(),
            TextField(
              controller: _freqController,
              decoration: InputDecoration(
                labelText: l10n.repeater_frequencyMhz,
                helperText: l10n.repeater_frequencyHelper,
                border: const OutlineInputBorder(),
                suffixText: 'MHz',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => _markChanged(_SettingField.radio),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _txPowerController,
                    decoration: InputDecoration(
                      labelText: l10n.repeater_txPower,
                      helperText: l10n.repeater_txPowerHelper,
                      border: const OutlineInputBorder(),
                      suffixText: 'dBm',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _markChanged(_SettingField.txPower),
                  ),
                ),
                const SizedBox(width: 8),
                _buildInlineRefreshButton(
                  isRefreshing: _refreshingTxPower,
                  onRefresh: _refreshTxPower,
                  tooltip: l10n.repeater_refreshTxPower,
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _bandwidth,
              decoration: InputDecoration(
                labelText: l10n.repeater_bandwidth,
                border: const OutlineInputBorder(),
              ),
              items: _bandwidthOptions.map((bw) {
                return DropdownMenuItem(
                  value: bw,
                  child: Text(_formatBandwidthLabel(bw)),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _bandwidth = value;
                  });
                  _markChanged(_SettingField.radio);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _spreadingFactor,
              decoration: InputDecoration(
                labelText: l10n.repeater_spreadingFactor,
                border: const OutlineInputBorder(),
              ),
              items: _spreadingFactorOptions.map((sf) {
                return DropdownMenuItem(value: sf, child: Text('SF$sf'));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _spreadingFactor = value;
                  });
                  _markChanged(_SettingField.radio);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _codingRate,
              decoration: InputDecoration(
                labelText: l10n.repeater_codingRate,
                border: const OutlineInputBorder(),
              ),
              items: _codingRateOptions.map((cr) {
                return DropdownMenuItem(value: cr, child: Text('4/$cr'));
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _codingRate = value;
                  });
                  _markChanged(_SettingField.radio);
                }
              },
            ),
            const SizedBox(height: 8),
            _buildFeatureToggleRow(
              title: l10n.repeater_rxGain,
              subtitle: l10n.repeater_rxGainHelper,
              value: _rxGainBoosted,
              isRefreshing: _refreshingRxGain,
              onChanged: (v) {
                setState(() => _rxGainBoosted = v);
                _markChanged(_SettingField.rxGain);
              },
              onRefresh: _refreshRxGain,
              refreshTooltip: l10n.repeater_refreshRxGain,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSettingsCard() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.location_on,
              title: l10n.repeater_locationSettings,
            ),
            const Divider(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _latController,
                    decoration: InputDecoration(
                      labelText: l10n.repeater_latitude,
                      helperText: l10n.repeater_latitudeHelper,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => _markChanged(_SettingField.lat),
                  ),
                ),
                const SizedBox(width: 8),
                _buildInlineRefreshButton(
                  isRefreshing: _refreshingLat,
                  onRefresh: _refreshLat,
                  tooltip: l10n.repeater_latitude,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _lonController,
                    decoration: InputDecoration(
                      labelText: l10n.repeater_longitude,
                      helperText: l10n.repeater_longitudeHelper,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    onChanged: (_) => _markChanged(_SettingField.lon),
                  ),
                ),
                const SizedBox(width: 8),
                _buildInlineRefreshButton(
                  isRefreshing: _refreshingLon,
                  onRefresh: _refreshLon,
                  tooltip: l10n.repeater_longitude,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureTogglesCard() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.toggle_on,
                  color: Theme.of(context).textTheme.headlineSmall?.color,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.repeater_features,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            _buildFeatureToggleRow(
              title: l10n.repeater_packetForwarding,
              subtitle: l10n.repeater_packetForwardingSubtitle,
              value: _repeatEnabled,
              isRefreshing: _refreshingRepeat,
              onChanged: (value) {
                setState(() {
                  _repeatEnabled = value;
                });
                _markChanged(_SettingField.repeat);
              },
              onRefresh: _refreshRepeat,
              refreshTooltip: l10n.repeater_refreshPacketForwarding,
            ),
            _buildFeatureToggleRow(
              title: l10n.repeater_guestAccess,
              subtitle: l10n.repeater_guestAccessSubtitle,
              value: _allowReadOnly,
              isRefreshing: _refreshingAllowReadOnly,
              onChanged: (value) {
                setState(() {
                  _allowReadOnly = value;
                });
                _markChanged(_SettingField.allowReadOnly);
              },
              onRefresh: _refreshAllowReadOnly,
              refreshTooltip: l10n.repeater_refreshGuestAccess,
            ),
            _buildFeatureToggleRow(
              title: l10n.repeater_multiAcks,
              subtitle: l10n.repeater_multiAcksSubtitle,
              value: _multiAcks,
              isRefreshing: _refreshingMultiAcks,
              onChanged: (v) {
                setState(() => _multiAcks = v);
                _markChanged(_SettingField.multiAcks);
              },
              onRefresh: _refreshMultiAcks,
              refreshTooltip: l10n.repeater_refreshMultiAcks,
            ),
            SwitchListTile(
              title: Text(l10n.repeater_clockSyncAfterLogin),
              subtitle: Text(l10n.repeater_clockSyncAfterLoginSubtitle),
              value: _autoClockSyncAfterLogin,
              onChanged: (value) async {
                setState(() {
                  _autoClockSyncAfterLogin = value;
                });
                await _storage.setRepeaterAutoClockSyncAfterLoginEnabled(
                  widget.repeater.publicKeyHex,
                  value,
                );
              },
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required bool isRefreshing,
    required ValueChanged<bool> onChanged,
    required VoidCallback onRefresh,
    required String refreshTooltip,
  }) {
    return Row(
      children: [
        Expanded(
          child: SwitchListTile(
            title: Text(title),
            subtitle: Text(subtitle),
            value: value,
            onChanged: onChanged,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        IconButton(
          icon: isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 20),
          onPressed: isRefreshing ? null : onRefresh,
          tooltip: refreshTooltip,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildAdvertisementSettingsCard() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.broadcast_on_personal,
              title: l10n.repeater_advertisementSettings,
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text(l10n.repeater_localAdvertInterval),
                    subtitle: Text(
                      l10n.repeater_localAdvertIntervalMinutes(_advertInterval),
                    ),
                    trailing: Switch(
                      value: _advertEnable,
                      onChanged: (value) {
                        setState(() {
                          _advertInterval = value ? 60 : 0;
                          _advertEnable = value;
                        });
                        _markChanged(_SettingField.advertInterval);
                      },
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                IconButton(
                  icon: _refreshingAdvertInterval
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: _refreshingAdvertInterval
                      ? null
                      : _refreshAdvertInterval,
                  tooltip: l10n.repeater_localAdvertInterval,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Slider(
              value: _advertInterval == 0
                  ? 60.toDouble()
                  : _advertInterval.toDouble(),
              min: 60,
              max: 240,
              divisions: 18,
              label: l10n.repeater_localAdvertIntervalMinutes(_advertInterval),
              onChanged: _advertEnable
                  ? (value) {
                      setState(() {
                        _advertInterval = value.toInt();
                      });
                      _markChanged(_SettingField.advertInterval);
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text(l10n.repeater_floodAdvertInterval),
                    subtitle: Text(
                      l10n.repeater_floodAdvertIntervalHours(
                        _floodAdvertInterval,
                      ),
                    ),
                    trailing: Switch(
                      value: _floodAdvertEnable,
                      onChanged: (value) {
                        setState(() {
                          _floodAdvertInterval = value ? 3 : 0;
                          _floodAdvertEnable = value;
                        });
                        _markChanged(_SettingField.floodAdvertInterval);
                      },
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                IconButton(
                  icon: _refreshingFloodAdvertInterval
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: _refreshingFloodAdvertInterval
                      ? null
                      : _refreshFloodAdvertInterval,
                  tooltip: l10n.repeater_floodAdvertInterval,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Slider(
              value: _floodAdvertInterval == 0
                  ? 3.toDouble()
                  : _floodAdvertInterval.toDouble(),
              min: 3,
              max: 168,
              divisions: 165,
              label: l10n.repeater_floodAdvertIntervalHours(
                _floodAdvertInterval,
              ),
              onChanged: _floodAdvertEnable
                  ? (value) {
                      setState(() {
                        _floodAdvertInterval = value.toInt();
                      });
                      _markChanged(_SettingField.floodAdvertInterval);
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text(l10n.repeater_floodMax),
                    subtitle: Text(l10n.repeater_floodMaxHelper),
                    trailing: Text(
                      '$_floodMax',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                IconButton(
                  icon: _refreshingFloodMax
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: _refreshingFloodMax ? null : _refreshFloodMax,
                  tooltip: l10n.repeater_floodMax,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Slider(
              value: _floodMax.toDouble(),
              min: 0,
              max: 64,
              divisions: 64,
              label: '$_floodMax',
              onChanged: (v) {
                setState(() => _floodMax = v.toInt());
                _markChanged(_SettingField.floodMax);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkHealthCard() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.health_and_safety,
              title: l10n.repeater_networkHealth,
            ),
            const Divider(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _loopDetect,
                    decoration: InputDecoration(
                      labelText: l10n.repeater_loopDetect,
                      helperText: l10n.repeater_loopDetectHelper,
                      helperMaxLines: 3,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'off',
                        child: Text(l10n.repeater_loopDetectOff),
                      ),
                      DropdownMenuItem(
                        value: 'minimal',
                        child: Text(l10n.repeater_loopDetectMinimal),
                      ),
                      DropdownMenuItem(
                        value: 'moderate',
                        child: Text(l10n.repeater_loopDetectModerate),
                      ),
                      DropdownMenuItem(
                        value: 'strict',
                        child: Text(l10n.repeater_loopDetectStrict),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _loopDetect = v);
                        _markChanged(_SettingField.loopDetect);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _buildInlineRefreshButton(
                  isRefreshing: _refreshingLoopDetect,
                  onRefresh: _refreshLoopDetect,
                  tooltip: l10n.repeater_loopDetect,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    title: Text(l10n.repeater_dutyCycle),
                    subtitle: Text(l10n.repeater_dutyCycleHelper),
                    trailing: Text(
                      l10n.repeater_dutyCyclePercent(_dutyCycle),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                IconButton(
                  icon: _refreshingDutyCycle
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: _refreshingDutyCycle ? null : _refreshDutyCycle,
                  tooltip: l10n.repeater_dutyCycle,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Slider(
              value: _dutyCycle.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              label: l10n.repeater_dutyCyclePercent(_dutyCycle),
              onChanged: (v) {
                setState(() => _dutyCycle = v.toInt());
                _markChanged(_SettingField.dutyCycle);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerInfoCard() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.person_outline,
              title: l10n.repeater_ownerInfo,
              tooltip: l10n.repeater_refreshOwnerInfo,
              isRefreshing: _refreshingOwnerInfo,
              onRefresh: _refreshOwnerInfo,
            ),
            const Divider(),
            TextField(
              controller: _ownerInfoController,
              decoration: InputDecoration(
                labelText: l10n.repeater_ownerInfo,
                helperText: l10n.repeater_ownerInfoHelper,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              maxLines: 4,
              minLines: 2,
              onChanged: (_) => _markChanged(_SettingField.ownerInfo),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flash_on,
                  color: Theme.of(context).textTheme.headlineSmall?.color,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.repeater_actionsTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.podcasts),
              title: Text(l10n.repeater_sendAdvert),
              subtitle: Text(l10n.repeater_sendAdvertSubtitle),
              enabled: !_runningAction,
              onTap: _runningAction
                  ? null
                  : () => _runAction('advert', l10n.repeater_sendAdvert),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.cell_tower),
              title: Text(l10n.repeater_sendAdvertZeroHop),
              subtitle: Text(l10n.repeater_sendAdvertZeroHopSubtitle),
              enabled: !_runningAction,
              onTap: _runningAction
                  ? null
                  : () => _runAction(
                      'advert.zerohop',
                      l10n.repeater_sendAdvertZeroHop,
                    ),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: Text(l10n.repeater_clockSync),
              subtitle: Text(l10n.repeater_clockSyncSubtitle),
              enabled: !_runningAction,
              onTap: _runningAction
                  ? null
                  : () => _runAction('clock sync', l10n.repeater_clockSync),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedCard() {
    final l10n = context.l10n;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.tune),
        title: Text(
          l10n.repeater_advancedSettings,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(l10n.repeater_advancedSettingsSubtitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _pathHashMode,
                  decoration: InputDecoration(
                    labelText: l10n.repeater_pathHashMode,
                    helperText: l10n.repeater_pathHashModeHelper,
                    helperMaxLines: 5,
                    border: const OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('0')),
                    DropdownMenuItem(value: 1, child: Text('1')),
                    DropdownMenuItem(value: 2, child: Text('2')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _pathHashMode = v);
                      _markChanged(_SettingField.pathHashMode);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              _buildInlineRefreshButton(
                isRefreshing: _refreshingPathHashMode,
                onRefresh: _refreshPathHashMode,
                tooltip: l10n.repeater_pathHashMode,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _txDelayController,
                  decoration: InputDecoration(
                    labelText: l10n.repeater_txDelay,
                    helperText: l10n.repeater_txDelayHelper,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _markChanged(_SettingField.txDelay),
                ),
              ),
              const SizedBox(width: 8),
              _buildInlineRefreshButton(
                isRefreshing: _refreshingTxDelay,
                onRefresh: _refreshTxDelay,
                tooltip: l10n.repeater_txDelay,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _directTxDelayController,
                  decoration: InputDecoration(
                    labelText: l10n.repeater_directTxDelay,
                    helperText: l10n.repeater_directTxDelayHelper,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _markChanged(_SettingField.directTxDelay),
                ),
              ),
              const SizedBox(width: 8),
              _buildInlineRefreshButton(
                isRefreshing: _refreshingDirectTxDelay,
                onRefresh: _refreshDirectTxDelay,
                tooltip: l10n.repeater_directTxDelay,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _intThreshController,
                  decoration: InputDecoration(
                    labelText: l10n.repeater_intThresh,
                    helperText: l10n.repeater_intThreshHelper,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _markChanged(_SettingField.intThresh),
                ),
              ),
              const SizedBox(width: 8),
              _buildInlineRefreshButton(
                isRefreshing: _refreshingIntThresh,
                onRefresh: _refreshIntThresh,
                tooltip: l10n.repeater_intThresh,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  title: Text(l10n.repeater_agcResetInterval),
                  subtitle: Text(l10n.repeater_agcResetIntervalHelper),
                  trailing: Text(
                    '${_agcResetInterval}s',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              IconButton(
                icon: _refreshingAgcResetInterval
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                onPressed: _refreshingAgcResetInterval
                    ? null
                    : _refreshAgcResetInterval,
                tooltip: l10n.repeater_agcResetInterval,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Slider(
            value: _agcResetInterval.toDouble(),
            min: 0,
            max: 240,
            divisions: 60,
            label: '${_agcResetInterval}s',
            onChanged: (v) {
              setState(() {
                // Clamp to multiple of 4 to match firmware semantics.
                _agcResetInterval = (v.toInt() ~/ 4) * 4;
              });
              _markChanged(_SettingField.agcResetInterval);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZoneCard() {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Text(
                  l10n.repeater_dangerZone,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.refresh, color: colorScheme.onErrorContainer),
              title: Text(
                l10n.repeater_rebootRepeater,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
              subtitle: Text(
                l10n.repeater_rebootRepeaterSubtitle,
                style: TextStyle(
                  color: colorScheme.onErrorContainer.withValues(alpha: 0.8),
                ),
              ),
              onTap: () => _confirmAction(
                l10n.repeater_rebootRepeater,
                l10n.repeater_rebootRepeaterConfirm,
                () => _sendDangerCommand('reboot'),
              ),
            ),
            // Regenerate identity key - hidden until fully implemented
            // ListTile(
            //   leading: Icon(Icons.vpn_key, color: colorScheme.onErrorContainer),
            //   title: Text('Regenerate Identity Key', style: TextStyle(color: colorScheme.onErrorContainer)),
            //   subtitle: Text(
            //     'Generate new public/private key pair',
            //     style: TextStyle(color: colorScheme.onErrorContainer.withValues(alpha: 0.8)),
            //   ),
            //   onTap: () => _confirmAction(
            //     'Regenerate Identity',
            //     'This will generate a new identity for the repeater. Continue?',
            //     () => _sendDangerCommand('regen key'),
            //   ),
            // ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: colorScheme.onErrorContainer,
              ),
              title: Text(
                l10n.repeater_eraseFileSystem,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
              subtitle: Text(
                l10n.repeater_eraseFileSystemSubtitle,
                style: TextStyle(
                  color: colorScheme.onErrorContainer.withValues(alpha: 0.8),
                ),
              ),
              onTap: () => _confirmAction(
                l10n.repeater_eraseFileSystem,
                l10n.repeater_eraseFileSystemConfirm,
                () => _sendDangerCommand('erase'),
                isDestructive: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendDangerCommand(String command) async {
    final l10n = context.l10n;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);

    if (command == 'erase') {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(l10n.repeater_eraseSerialOnly),
        );
      }
      return;
    }

    try {
      final selection = await connector.preparePathForContactSend(repeater);
      final timestampSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      connector.trackRepeaterAck(
        contact: repeater,
        selection: selection,
        text: command,
        timestampSeconds: timestampSeconds,
      );
      final frame = buildSendCliCommandFrame(
        repeater.publicKey,
        command,
        timestampSeconds: timestampSeconds,
      );
      await connector.sendFrame(frame);

      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(l10n.repeater_commandSent(command)),
        );
      }
    } catch (e) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(l10n.repeater_errorSendingCommand(e.toString())),
          backgroundColor: Colors.red,
        );
      }
    }
  }

  void _confirmAction(
    String title,
    String message,
    VoidCallback onConfirm, {
    bool isDestructive = false,
  }) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            child: Text(l10n.repeater_confirm),
          ),
        ],
      ),
    );
  }
}
