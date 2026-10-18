import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore_open/utils/app_logger.dart';
import 'package:meshcore_open/utils/module_diagnostic_logger.dart';

// Target the public stub even when mco_service is overridden by lib_serv.
// ignore: avoid_relative_lib_imports
import '../../packages/mco_service_stub/lib/mco_service.dart' as stub;

class _Logger extends Fake implements AppLogger {
  bool enabled = false;
  final events = <String>[];
  @override
  bool get isEnabled => enabled;
  @override
  void info(String message, {String tag = 'App', bool noNotify = false}) =>
      events.add('info/$tag/$noNotify/$message');
  @override
  void warn(String message, {String tag = 'App', bool noNotify = false}) =>
      events.add('warning/$tag/$noNotify/$message');
  @override
  void error(String message, {String tag = 'App', bool noNotify = false}) =>
      events.add('error/$tag/$noNotify/$message');
}

void main() {
  test('public stub accepts optional diagnostic hooks without invoking them', () {
    final service = stub.SettingsSectionsService();
    var calls = 0;
    service.attachDiagnosticLogger((_) { calls++; }, diagnostics: (_, _, _) {
      calls++;
      return true;
    });
    expect(calls, 0);
    service.dispose();
  });

  test('disabled app logging defers optional module diagnostics', () {
    final logger = _Logger();
    expect(logModuleDiagnostic('fixture', 'Module', 'info', logger: logger), isFalse);
    expect(logger.events, isEmpty);
    logger.enabled = true;
    expect(logModuleDiagnostic('fixture', 'Module', 'info', logger: logger), isTrue);
    expect(logger.events, <String>['info/Module/true/fixture']);
  });

  test('module diagnostics preserve levels and tags without notifying observers', () {
    final logger = _Logger()..enabled = true;
    for (final level in <String>['info', 'warning', 'error', 'unknown']) {
      expect(logModuleDiagnostic('fixture', 'Module', level, logger: logger), isTrue);
    }
    expect(logger.events, <String>[
      'info/Module/true/fixture',
      'warning/Module/true/fixture',
      'error/Module/true/fixture',
      'info/Module/true/fixture',
    ]);
  });
}
