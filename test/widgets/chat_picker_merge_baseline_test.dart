import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/widgets/emoji_picker.dart';
import 'package:meshcore_open/widgets/gif_picker.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';

// Global IO override keeps Flutter frame callbacks synthetic even when they
// run outside the zone in which the picker was opened. No real network.
class _Network extends HttpOverrides {
  MockClient? client;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);
}

class _Client extends Fake implements HttpClient {
  _Client(this.network);
  final _Network network;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _Request(network, url);
  @override
  void close({bool force = false}) {}
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String, List<String>) action) {}
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.network, this.url);
  final _Network network;
  final Uri url;
  @override
  final HttpHeaders headers = _Headers();
  @override
  set followRedirects(bool value) {}
  @override
  set maxRedirects(int value) {}
  @override
  set contentLength(int value) {}
  @override
  set persistentConnection(bool value) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();
  @override
  Future<HttpClientResponse> close() async {
    final client = network.client;
    if (client == null) {
      throw StateError('Unexpected picker HTTP request');
    }
    return _Response(await client.get(url));
  }
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.response);
  final http.Response response;
  @override
  int get statusCode => response.statusCode;
  @override
  int get contentLength => response.bodyBytes.length;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  bool get persistentConnection => false;
  @override
  String get reasonPhrase => response.reasonPhrase ?? 'Synthetic response';
  @override
  HttpHeaders get headers => _Headers();
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(response.bodyBytes).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Unexpected synthetic HTTP response access: ${invocation.memberName}',
  );
}

Future<void> _show(
  WidgetTester tester,
  WidgetBuilder content, {
  bool meshSheet = true,
  double keyboard = 0,
  double navigation = 0,
  Size size = const Size(640, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewInsets: EdgeInsets.only(bottom: keyboard),
        viewPadding: EdgeInsets.only(bottom: navigation),
        padding: EdgeInsets.only(bottom: navigation),
      ),
      child: child!,
    ),
    home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () {
        if (meshSheet) {
          showMeshSheet<void>(context, builder: content);
        } else {
          // Retained for comparison with the pre-merge bare modal.
          showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: content);
        }
      },
      child: const Text('Open picker'),
    ))),
  ));
  await tester.tap(find.text('Open picker'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _finishRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late HttpOverrides? previousNetwork;
  late _Network network;
  setUp(() {
    previousNetwork = HttpOverrides.current;
    network = _Network();
    HttpOverrides.global = network;
  });
  tearDown(() => HttpOverrides.global = previousNetwork);
  for (final sample in [
    (name: 'desktop', size: const Size(640, 1000), nav: 0.0, keyboard: 0.0),
    (name: 'gesture bar', size: const Size(640, 1000), nav: 24.0, keyboard: 0.0),
    (name: 'button bar', size: const Size(640, 1000), nav: 48.0, keyboard: 0.0),
    (name: 'keyboard overlaps navigation', size: const Size(640, 1000), nav: 24.0, keyboard: 300.0),
    (name: 'landscape keyboard', size: const Size(640, 360), nav: 24.0, keyboard: 140.0),
  ]) {
    testWidgets('sheet handles ${sample.name} exactly once', (tester) async {
      const outer = ValueKey('outer-body');
      const inner = ValueKey('inner-body');
      MediaQueryData? childMedia;
      await _show(tester, (context) {
        childMedia = MediaQuery.of(context);
        return const SizedBox(key: outer, height: 100,
          child: SafeArea(top: false, child: SizedBox.expand(key: inner)),
        );
      }, size: sample.size, navigation: sample.nav, keyboard: sample.keyboard);
      final gap = sample.keyboard > sample.nav ? sample.keyboard : sample.nav;
      expect(tester.getRect(find.byKey(outer)).bottom, closeTo(sample.size.height - gap, 0.01));
      expect(tester.getRect(find.byKey(inner)), tester.getRect(find.byKey(outer)));
      expect(childMedia!.viewInsets.bottom, 0);
      expect(childMedia!.viewPadding.bottom, 0);
      expect(childMedia!.padding.bottom, 0);
      Navigator.of(tester.element(find.byKey(outer))).pop();
      await _finishRoute(tester);
    });
  }

  for (final state in ['results', 'empty', 'error']) {
    testWidgets('GIF $state fits above keyboard without re-fetching on rebuild', (tester) async {
      var requests = 0;
      final selected = <String>[];
      network.client = MockClient((_) async {
        requests++;
        return http.Response(state == 'results'
          ? '{"data":[{"id":"synthetic-gif","images":{}}]}' : '{"data":[]}',
          state == 'error' ? 503 : 200);
      });
      await _show(tester, (_) => GifPicker(onGifSelected: selected.add),
        size: const Size(640, 400), navigation: 24, keyboard: 180);
      await tester.pump();
      expect(tester.getRect(find.byType(GifPicker)).bottom, lessThanOrEqualTo(220));
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();
      expect(requests, 1);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'draft');
      expect(tester.takeException(), isNull);
      await tester.tap(find.descendant(of: find.byType(GifPicker), matching: find.byIcon(Icons.close)));
      await _finishRoute(tester);
      expect(selected, isEmpty);
    });
  }

  testWidgets('baseline: reaction selection calls back once and dismisses', (tester) async {
    final selected = <String>[];
    await _show(tester, (_) => EmojiPicker(onEmojiSelected: selected.add), navigation: 24);
    final grid = find.byType(TabBarView);
    expect(tester.getRect(grid).bottom, lessThanOrEqualTo(976));
    await tester.tap(find.text('👍').first);
    await _finishRoute(tester);
    expect(selected, ['👍']);
    expect(find.byType(EmojiPicker), findsNothing);
  });

  testWidgets('baseline: closing reactions does not choose an emoji', (tester) async {
    final selected = <String>[];
    await _show(tester, (_) => EmojiPicker(onEmojiSelected: selected.add));
    await tester.tap(find.descendant(of: find.byType(EmojiPicker), matching: find.byIcon(Icons.close)));
    await _finishRoute(tester);
    expect(selected, isEmpty);
    expect(find.byType(EmojiPicker), findsNothing);
  });

  testWidgets('baseline: GIF typing makes no requests until submit and selection returns its ID', (tester) async {
    final requests = <Uri>[];
    final selected = <String>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response(jsonEncode({'data': [
        {'id': 'synthetic-gif', 'images': <String, Object>{}},
      ]}), 200);
    });
    network.client = client;
    await (() async {
      await _show(tester, (_) => GifPicker(onGifSelected: selected.add));
      await tester.pump();
      expect(requests, hasLength(1));
      expect(requests.single.path, endsWith('/trending'));
      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();
      expect(requests, hasLength(1));
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(requests, hasLength(2));
      expect(requests.last.queryParameters['q'], 'hello world');
      // The fixture has no preview URL, hence no image download/decoder.
      final grid = find.byType(GridView);
      final tile = find.descendant(of: grid, matching: find.byIcon(Icons.gif_box));
      await tester.tap(tile);
      await _finishRoute(tester);
      expect(selected, ['synthetic-gif']);
      expect(find.byType(GifPicker), findsNothing);
    })();
  });

  testWidgets('baseline: closing GIF picker returns no selection or extra request', (tester) async {
    var requests = 0;
    final selected = <String>[];
    final client = MockClient((_) async {
      requests++;
      return http.Response('{"data":[]}', 200);
    });
    network.client = client;
    await (() async {
      await _show(tester, (_) => GifPicker(onGifSelected: selected.add));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byType(GifPicker), matching: find.byIcon(Icons.close)));
      await _finishRoute(tester);
      expect(selected, isEmpty);
      expect(requests, 1);
      expect(find.byType(GifPicker), findsNothing);
    })();
  });

  testWidgets('baseline: GIF retry is explicit and does not loop automatically', (tester) async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(requests == 1 ? 'synthetic failure' : '{"data":[]}', requests == 1 ? 503 : 200);
    });
    network.client = client;
    await (() async {
      await _show(tester, (_) => GifPicker(onGifSelected: (_) {}));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(requests, 1);
      await tester.tap(find.byWidgetPredicate((widget) => widget is ElevatedButton));
      await tester.pump();
      expect(requests, 2);
      expect(find.byType(GridView), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    })();
  });

  testWidgets('baseline: shared sheet reserves the keyboard space once', (tester) async {
    const content = ValueKey('sheet-content');
    await _show(tester, (_) => const SizedBox(key: content, height: 100, child: Text('Body')),
      meshSheet: true, keyboard: 200);
    expect(tester.getRect(find.byKey(content)).bottom, closeTo(800, 0.01));
    Navigator.of(tester.element(find.byKey(content))).pop();
    await _finishRoute(tester);
    expect(find.byKey(content), findsNothing);
  });
}
