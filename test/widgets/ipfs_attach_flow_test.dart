import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/helpers/ipfs_link_attach_flow.dart';
import 'package:meshcore_open/helpers/ipfs_upload_helper.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';

class _Settings extends AppSettingsService {
  @override
  AppSettings get settings => AppSettings(
    uploadIpfsEndpoint: 'https://api.pinata.cloud/pinning/pinFileToIPFS',
    uploadIpfsApiKey: 'synthetic-token',
  );
}

class _Picker {
  int calls = 0;
  Future<XFile?> Function() pick = () async => null;
  Future<XFile?> openFile() {
    calls++;
    return pick();
  }
}

void main() {
  late _Picker picker;
  late _Settings settings;
  late TextEditingController controller;
  late FocusNode focus;
  late MockClient client;
  late Future<void> completion;
  late int requests;
  late Future<http.Response> Function(http.Request) respond;

  setUp(() {
    picker = _Picker();
    settings = _Settings();
    controller = TextEditingController(text: '  черновик 👩‍💻\n  ');
    focus = FocusNode();
    requests = 0;
    respond = (_) async => http.Response('{"IpfsHash":"bafytest"}', 200);
    client = MockClient((request) {
      requests++;
      return respond(request);
    });
    IpfsUploadHelper.httpClient = client;
  });

  tearDown(() {
    IpfsUploadHelper.httpClient = null;
    client.close();
    controller.dispose();
    focus.dispose();
    settings.dispose();
  });

  Future<void> show(WidgetTester tester, {bool Function(String)? fits}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsService>.value(
        value: settings,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Builder(builder: (context) => Column(children: [
            TextField(controller: controller, focusNode: focus),
            TextButton(
              key: const ValueKey('attach'),
              onPressed: () {
                completion = attachIpfsLinkToDraft(
                  context: context,
                  controller: controller,
                  focusNode: focus,
                  maxBytes: 200,
                  encodeOutbound: (text) => text,
                  draftFits: fits,
                  pickFile: picker.openFile,
                );
              },
              child: const Text('Attach'),
            ),
          ]))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(picker.calls, 0);
    expect(requests, 0);
  }

  Future<void> attach(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('attach')));
    await tester.pump();
  }

  XFile file() => XFile.fromData(
    Uint8List.fromList([1, 2, 3]), name: 'photo.png', path: 'photo.png',
  );

  testWidgets('no upload on construction or cancelled selection', (tester) async {
    final original = controller.value;
    await show(tester);
    await attach(tester);
    await completion;
    expect(picker.calls, 1);
    expect(requests, 0);
    expect(controller.value, original);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('payload budget rejects before picker or upload', (tester) async {
    final original = controller.value;
    await show(tester, fits: (_) => false);
    await attach(tester);
    await completion;
    expect(picker.calls, 0);
    expect(requests, 0);
    expect(controller.value, original);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('upload adds link to the latest draft without trimming it', (tester) async {
    final response = Completer<http.Response>();
    respond = (_) => response.future;
    picker.pick = () async => file();
    await show(tester);
    await attach(tester);
    expect(requests, 1);
    controller.text = '  новый черновик\n  ';
    response.complete(http.Response('{"IpfsHash":"bafytest"}', 200));
    await completion;
    await tester.pump();
    expect(controller.text, 'ipfs://bafytest\n  новый черновик\n  ');
    expect(controller.selection.baseOffset, controller.text.length);
    expect(requests, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failure preserves the draft and hides server secrets', (tester) async {
    final original = controller.value;
    picker.pick = () async => file();
    respond = (_) async => http.Response('echo synthetic-token', 500);
    await show(tester);
    await attach(tester);
    await completion;
    await tester.pump();
    expect(controller.value, original);
    expect(find.textContaining('synthetic-token'), findsNothing);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('budget change during upload keeps the whole over-limit draft', (tester) async {
    var fits = true;
    final response = Completer<http.Response>();
    respond = (_) => response.future;
    picker.pick = () async => file();
    await show(tester, fits: (_) => fits);
    await attach(tester);
    final draft = controller.text;
    fits = false;
    response.complete(http.Response('{"IpfsHash":"bafytest"}', 200));
    await completion;
    await tester.pump();
    expect(controller.text, 'ipfs://bafytest\n$draft');
    expect(find.textContaining('message is now too long'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completion after screen disposal cannot change its draft', (tester) async {
    final original = controller.value;
    final response = Completer<http.Response>();
    respond = (_) => response.future;
    picker.pick = () async => file();
    await show(tester);
    await attach(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    response.complete(http.Response('{"IpfsHash":"bafytest"}', 200));
    await completion;
    await tester.pump();
    expect(controller.value, original);
    expect(tester.takeException(), isNull);
  });
}
