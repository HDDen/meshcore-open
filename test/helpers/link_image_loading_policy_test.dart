import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/helpers/message_url_image_helper.dart';

const _image = 'https://images.example/photo.png';

void main() {
  late MockClient client;
  late List<Uri> requests;
  late List<String> verifications;
  late Future<http.Response> Function(http.Request) respond;
  late Future<bool> Function(String) verify;

  setUp(() {
    requests = [];
    verifications = [];
    respond = (_) async => http.Response('<meta property="og:image" content="$_image">', 200);
    verify = (_) async => true;
    client = MockClient((request) {
      requests.add(request.url);
      return respond(request);
    });
    MessageUrlImageHelper.httpClient = client;
    MessageUrlImageHelper.verifyImageForTest = (url) {
      verifications.add(url);
      return verify(url);
    };
    MessageUrlImageHelper.loadLinkImages.value = false;
    MessageUrlImageHelper.loadLinkImages.value = true;
  });
  tearDown(() {
    MessageUrlImageHelper.loadLinkImages.value = true;
    MessageUrlImageHelper.httpClient = null;
    MessageUrlImageHelper.verifyImageForTest = null;
    client.close();
  });

  test('master off blocks every parsing path before HTTP or image verification', () async {
    MessageUrlImageHelper.loadLinkImages.value = false;
    for (final text in [
      _image, 'https://ibb.co/example', 'https://pyx.li/?i=abc',
      'ipfs://bafyexample', 'https://gateway.example/ipfs/bafyexample',
    ]) {
      expect(MessageUrlImageHelper.hasPotentialImageUrl(text), isTrue);
      expect(await MessageUrlImageHelper.parse(text), isNull);
      expect(await MessageUrlImageHelper.parseVerified(text), isNull);
      expect(await MessageUrlImageHelper.parseVerifiedForMessage(text, text), isNull);
    }
    expect(requests, isEmpty);
    expect(verifications, isEmpty);
  });

  test('cache cannot bypass master off; re-enabling starts a fresh generation', () async {
    final first = MessageUrlImageHelper.parseVerifiedForMessage('cached', _image);
    expect(await first, _image);
    expect(identical(first, MessageUrlImageHelper.parseVerifiedForMessage('cached', _image)), isTrue);
    expect(verifications, [_image]);
    MessageUrlImageHelper.loadLinkImages.value = false;
    expect(await MessageUrlImageHelper.parseVerifiedForMessage('cached', _image), isNull);
    expect(verifications, [_image]);
    MessageUrlImageHelper.loadLinkImages.value = true;
    expect(await MessageUrlImageHelper.parseVerifiedForMessage('cached', _image), _image);
    expect(verifications, [_image, _image]);
    expect(requests, isEmpty);
  });

  for (final reenable in [false, true]) {
    test('an old sharing-page response cannot start a new image fetch (reenable=$reenable)', () async {
      final started = Completer<void>();
      final page = Completer<http.Response>();
      respond = (_) {
        started.complete();
        return page.future;
      };
      final result = MessageUrlImageHelper.parseVerified('https://ibb.co/pending');
      await started.future;
      MessageUrlImageHelper.loadLinkImages.value = false;
      if (reenable) MessageUrlImageHelper.loadLinkImages.value = true;
      page.complete(http.Response('<meta property="og:image" content="$_image">', 200));
      expect(await result, isNull);
      expect(requests, hasLength(1));
      expect(verifications, isEmpty);
    });
  }

  test('late verification cannot restore the previous cache generation', () async {
    final started = Completer<void>();
    final pending = Completer<bool>();
    verify = (_) {
      if (!started.isCompleted) {
        started.complete();
        return pending.future;
      }
      return Future<bool>.value(true);
    };
    final old = MessageUrlImageHelper.parseVerifiedForMessage('late', _image);
    await started.future;
    MessageUrlImageHelper.loadLinkImages.value = false;
    MessageUrlImageHelper.loadLinkImages.value = true;
    pending.complete(true);
    expect(await old, isNull);
    expect(await MessageUrlImageHelper.parseVerifiedForMessage('late', _image), _image);
    expect(verifications, [_image, _image]);
  });

  testWidgets('preview hides immediately and releases its policy listener', (tester) async {
    try {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: MessageUrlImageFutureBuilder(
          messageId: 'visible', text: _image,
          builder: (context, snapshot) => Text(snapshot.data ?? 'hidden'),
        ),
      )));
      await tester.pumpAndSettle();
      expect(find.text(_image), findsOneWidget);
      MessageUrlImageHelper.loadLinkImages.value = false;
      await tester.pump();
      expect(find.text(_image), findsNothing);
      expect(find.text('hidden'), findsOneWidget);
      MessageUrlImageHelper.loadLinkImages.value = true;
      await tester.pumpAndSettle();
      expect(find.text(_image), findsOneWidget);
      final before = verifications.length;
      await tester.pumpWidget(const SizedBox.shrink());
      MessageUrlImageHelper.loadLinkImages.value = false;
      await tester.pump();
      expect(verifications.length, before);
      expect(tester.takeException(), isNull);
    } finally {
      // Unmount even after an assertion fails, before tearDown resets policy
      // and removes the synthetic verifier. Never fall through to native IO.
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
