import '../l10n/app_localizations.dart';

/// Локальный API 66: MyMesh::handleCommand -> CommonRadioPrefs/board.
/// Каталог не импортирует полный набор команд репитера или Serial Rescue.
const companionCliQuickCommands = [
  'ver', 'board', 'get name', 'get radio', 'get tx',
  'set pin <PIN>', 'reboot', 'poweroff', 'shutdown',
  'get cad', 'get radio.rxgain', 'get rxdelay', 'get agc.reset.interval',
  'get multi.acks', 'get txdelay', 'get direct.txdelay',
  'get wifi.ssid', 'get wifi.pwd', 'get wifi.enabled', 'get wifi.status',
  'get wifi.ip', 'set wifi.clear',
];

/// Для PIN подставляется заготовка, а не число, меняющее настройки ноды.
String companionCliCommandExample(String command) =>
    command == 'set pin <PIN>' ? 'set pin ' : command;

class CompanionCliHelpEntry {
  const CompanionCliHelpEntry(this.command, this.description);
  final String command;
  final String description;
}

class CompanionCliHelpSection {
  const CompanionCliHelpSection(this.title, this.commands, {this.note});
  final String title;
  final List<CompanionCliHelpEntry> commands;
  final String? note;
}

List<CompanionCliHelpSection> companionCliHelpSections(AppLocalizations l10n) => [
  CompanionCliHelpSection(l10n.repeater_general, [
    CompanionCliHelpEntry('ver', l10n.repeater_cliHelpVersion),
    CompanionCliHelpEntry('board', l10n.repeater_cliHelpBoard),
  ]),
  CompanionCliHelpSection(l10n.repeater_getCategory, [
    CompanionCliHelpEntry('get name', l10n.repeater_cliHelpGetName),
    CompanionCliHelpEntry('get tz.offset', l10n.companionCli_helpGetTimezone),
    CompanionCliHelpEntry('get radio', l10n.repeater_cliHelpGetRadio),
    CompanionCliHelpEntry('get freq', l10n.repeater_cliHelpGetFreq),
    CompanionCliHelpEntry('get tx', l10n.repeater_cliHelpGetTx),
    CompanionCliHelpEntry('get af', l10n.repeater_cliHelpGetAf),
    CompanionCliHelpEntry('get dutycycle', l10n.repeater_cliHelpGetDutyCycle),
    CompanionCliHelpEntry('get int.thresh', l10n.repeater_cliHelpGetIntThresh),
    CompanionCliHelpEntry('get cad', l10n.companionCli_helpGetCad),
    CompanionCliHelpEntry('get radio.rxgain', l10n.companionCli_helpGetRxGain),
    CompanionCliHelpEntry('get rxdelay', l10n.repeater_cliHelpGetRxDelay),
    CompanionCliHelpEntry('get agc.reset.interval', l10n.repeater_cliHelpGetAgcResetInterval),
    CompanionCliHelpEntry('get path.hash.mode', l10n.companionCli_helpGetPathHashMode),
    CompanionCliHelpEntry('get multi.acks', l10n.repeater_cliHelpGetMultiAcks),
    CompanionCliHelpEntry('get txdelay', l10n.repeater_cliHelpGetTxDelay),
    CompanionCliHelpEntry('get direct.txdelay', l10n.repeater_cliHelpGetDirectTxDelay),
  ]),
  CompanionCliHelpSection(l10n.repeater_settingsCategory, [
    CompanionCliHelpEntry('set name <name>', l10n.repeater_cliHelpSetName),
    CompanionCliHelpEntry('set pin <PIN>', l10n.companionCli_helpSetPin),
    CompanionCliHelpEntry('set tz.offset <hours>', l10n.companionCli_helpSetTimezone),
    CompanionCliHelpEntry('set radio <freq>,<bw>,<sf>,<cr>', l10n.repeater_cliHelpSetRadio),
    CompanionCliHelpEntry('set tx <dBm>', l10n.companionCli_helpSetTx),
    CompanionCliHelpEntry('set af <0..9>', l10n.repeater_cliHelpSetAf),
    CompanionCliHelpEntry('set dutycycle <1..100>', l10n.repeater_cliHelpSetDutyCycle),
    CompanionCliHelpEntry('set int.thresh <dB>', l10n.repeater_cliHelpSetIntThresh),
    CompanionCliHelpEntry('set cad <on|off>', l10n.companionCli_helpSetCad),
    CompanionCliHelpEntry('set radio.rxgain <on|off>', l10n.companionCli_helpSetRxGain),
    CompanionCliHelpEntry('set rxdelay <0..20>', l10n.repeater_cliHelpSetRxDelay),
    CompanionCliHelpEntry('set agc.reset.interval <seconds>', l10n.repeater_cliHelpSetAgcResetInterval),
    CompanionCliHelpEntry('set path.hash.mode <0|1|2>', l10n.repeater_cliHelpSetPathHashMode),
    CompanionCliHelpEntry('set multi.acks <0|1>', l10n.repeater_cliHelpSetMultiAcks),
    CompanionCliHelpEntry('set txdelay <0..2>', l10n.repeater_cliHelpSetTxDelay),
    CompanionCliHelpEntry('set direct.txdelay <0..2>', l10n.repeater_cliHelpSetDirectTxDelay),
  ]),
  CompanionCliHelpSection(l10n.repeater_powerMgmt, [
    CompanionCliHelpEntry('reboot', l10n.repeater_cliHelpReboot),
    CompanionCliHelpEntry('poweroff', l10n.repeater_cliHelpPowerOff),
    CompanionCliHelpEntry('shutdown', l10n.repeater_cliHelpPowerOff),
  ]),
  CompanionCliHelpSection(l10n.companionCli_helpWifiTitle, [
    CompanionCliHelpEntry('get wifi.ssid', l10n.companionCli_helpGetWifiSsid),
    CompanionCliHelpEntry('get wifi.pwd', l10n.companionCli_helpGetWifiPassword),
    CompanionCliHelpEntry('get wifi.enabled', l10n.companionCli_helpGetWifiEnabled),
    CompanionCliHelpEntry('get wifi.status', l10n.companionCli_helpGetWifiStatus),
    CompanionCliHelpEntry('get wifi.ip', l10n.companionCli_helpGetWifiIp),
    CompanionCliHelpEntry('set wifi.ssid <SSID>', l10n.companionCli_helpSetWifiSsid),
    CompanionCliHelpEntry('set wifi.pwd <password>', l10n.companionCli_helpSetWifiPassword),
    CompanionCliHelpEntry('set wifi.enabled <0|1>', l10n.companionCli_helpSetWifiEnabled),
    CompanionCliHelpEntry('set wifi.clear', l10n.companionCli_helpClearWifi),
  ], note: l10n.companionCli_helpWifiNote),
  CompanionCliHelpSection(l10n.companionCli_helpHardwareTitle, [
    CompanionCliHelpEntry('get radio.fem.rxgain', l10n.repeater_cliHelpGetRadioFemRxGain),
    CompanionCliHelpEntry('set radio.fem.rxgain <on|off>', l10n.repeater_cliHelpSetRadioFemRxGain),
    CompanionCliHelpEntry('get radio.fem.txgain', l10n.repeater_cliHelpGetRadioFemTxGain),
    CompanionCliHelpEntry('set radio.fem.txgain <on|off>', l10n.repeater_cliHelpSetRadioFemTxGain),
    CompanionCliHelpEntry('get fan', l10n.companionCli_helpGetFan),
    CompanionCliHelpEntry('set fan <on|off|auto>', l10n.companionCli_helpSetFan),
    CompanionCliHelpEntry('set fan.lo <degrees>', l10n.companionCli_helpSetFanLow),
    CompanionCliHelpEntry('set fan.hi <degrees>', l10n.companionCli_helpSetFanHigh),
  ], note: l10n.companionCli_helpHardwareNote),
];
