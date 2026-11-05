import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/services/node_banner_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _record =
    'v=1;on=1;url=https%3A%2F%2Fshop.example.com%2Fnode%3Fref%3Da%26b%3Dc;'
    'title=Need%20a%20node%3F';

String _doh(String data, {int status = 0, int ttl = 300}) => jsonEncode({
  'Status': status,
  'Answer': [
    {'name': '_banner.meshcoreopen.org', 'type': 16, 'TTL': ttl, 'data': data},
  ],
});

class _NoPreferencesDirectory extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async {
    throw MissingPluginException('synthetic DNS banner preferences');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform previousPaths;

  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _NoPreferencesDirectory();
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(() {
    PathProviderPlatform.instance = previousPaths;
    PrefsManager.reset();
  });

  test('disabled production service never creates an HTTP client', () async {
    var clientCreations = 0;
    // Even direct construction/load must remain inert without initialized
    // preferences. No fallback request is allowed when the gate is off.
    PrefsManager.reset();
    await HttpOverrides.runZoned(
      () async {
        final service = NodeBannerService();
        expect(await service.load(), isNull);
        expect(await service.load(), isNull);
      },
      createHttpClient: (_) {
        clientCreations++;
        throw const SocketException('Unexpected banner network access');
      },
    );
    expect(clientCreations, 0);
  });

  test('cached on=1 cannot bypass the production service gate', () async {
    final prefs = PrefsManager.instance;
    await prefs.setString('node_banner_txt', _record);
    await prefs.setInt(
      'node_banner_expires_ms',
      DateTime.utc(2100).millisecondsSinceEpoch,
    );
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(_doh('"$_record"'), 200);
    });
    addTearDown(client.close);
    expect(await NodeBannerService(client: client).load(), isNull);
    expect(requests, 0);
    expect(prefs.getString('node_banner_txt'), _record);
  });

  group('NodeBannerConfig.parse', () {
    test('reads the link and decodes text overrides', () {
      final config = NodeBannerConfig.parse(_record)!;
      expect(config.url.toString(), 'https://shop.example.com/node?ref=a&b=c');
      expect(config.title, 'Need a node?');
      expect(config.body, isNull);
      expect(config.action, isNull);
    });

    test('accepts plain-text values', () {
      final config = NodeBannerConfig.parse(
        'v=1;on=1;url=https://shop.example.com/node?ref=a&b=c;'
        'title=Need a new node?;body=Waterproof, 50% off this week.;'
        'cta=Get one here',
      )!;
      expect(config.url.toString(), 'https://shop.example.com/node?ref=a&b=c');
      expect(config.title, 'Need a new node?');
      expect(config.body, 'Waterproof, 50% off this week.');
      expect(config.action, 'Get one here');
    });

    test('is off for on=0, unknown versions, and non-https links', () {
      expect(
        NodeBannerConfig.parse(_record.replaceAll('on=1', 'on=0')),
        isNull,
      );
      expect(NodeBannerConfig.parse(_record.replaceAll('v=1', 'v=2')), isNull);
      expect(NodeBannerConfig.parse('v=1;on=1;url=http%3A%2F%2Fx.com'), isNull);
      expect(NodeBannerConfig.parse('v=1;on=1'), isNull);
      expect(NodeBannerConfig.parse('v=1;on=1;url=%E0%A4%A'), isNull);
    });
  });

  test('joins split TXT character-strings and unescapes them', () {
    final answer = NodeBannerService.txtFromDohJson(
      _doh(r'"v=1;on=1;url=https%3A%2F%2Fa.com" ";title=Say \"hi\""'),
    )!;
    expect(answer.text, 'v=1;on=1;url=https%3A%2F%2Fa.com;title=Say "hi"');
    expect(answer.ttl, 300);
  });

  test('no record or NXDOMAIN gives no answer', () {
    expect(NodeBannerService.txtFromDohJson(jsonEncode({'Status': 3})), isNull);
    expect(NodeBannerService.txtFromDohJson(jsonEncode({'Status': 0})), isNull);
  });

  test('load queries Cloudflare DoH and caches for the TTL', () async {
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final client = MockClient((request) async {
      calls++;
      expect(request.url.host, 'cloudflare-dns.com');
      expect(request.url.queryParameters['name'], '_banner.meshcoreopen.org');
      expect(request.url.queryParameters['type'], 'TXT');
      expect(request.headers['accept'], 'application/dns-json');
      return http.Response(_doh('"$_record"'), 200);
    });
    addTearDown(client.close);
    final service = NodeBannerService.forTesting(client: client, now: () => now);

    expect((await service.load())?.title, 'Need a node?');
    expect((await service.load())?.title, 'Need a node?');
    expect(calls, 1);

    now = now.add(const Duration(minutes: 6));
    await service.load();
    expect(calls, 2);
  });

  test('load returns null when the lookup fails', () async {
    final failingClient = MockClient(
      (_) async => throw http.ClientException('offline'),
    );
    addTearDown(failingClient.close);
    final failing = NodeBannerService.forTesting(client: failingClient);
    expect(await failing.load(), isNull);

    final errorClient = MockClient((_) async => http.Response('', 503));
    addTearDown(errorClient.close);
    final serverError = NodeBannerService.forTesting(client: errorClient);
    expect(await serverError.load(), isNull);
  });

  for (final entry in [(0, 60), (100000, 21600)]) {
    test('DNS TTL ${entry.$1} is bounded to ${entry.$2} seconds', () async {
      var requests = 0;
      var now = DateTime.utc(2026, 1, 1);
      final client = MockClient((_) async {
        requests++;
        return http.Response(_doh('"$_record"', ttl: entry.$1), 200);
      });
      addTearDown(client.close);
      final service = NodeBannerService.forTesting(
        client: client,
        now: () => now,
      );
      expect(await service.load(), isNotNull);
      now = now.add(Duration(seconds: entry.$2 - 1));
      expect(await service.load(), isNotNull);
      expect(requests, 1);
      now = now.add(const Duration(seconds: 1));
      expect(await service.load(), isNotNull);
      expect(requests, 2);
    });
  }

  test('a cached off record prevents another lookup until expiry', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response(_doh('"v=1;on=0"'), 200);
    });
    addTearDown(client.close);
    final service = NodeBannerService.forTesting(client: client);
    expect(await service.load(), isNull);
    expect(await service.load(), isNull);
    expect(requests, 1);
  });

  test('malformed DoH JSON is hidden and is not saved as configuration', () async {
    final client = MockClient((_) async => http.Response('{broken', 200));
    addTearDown(client.close);
    expect(
      await NodeBannerService.forTesting(client: client).load(),
      isNull,
    );
    expect(PrefsManager.instance.getString('node_banner_txt'), isNull);
    expect(PrefsManager.instance.getInt('node_banner_expires_ms'), isNull);
  });
}
