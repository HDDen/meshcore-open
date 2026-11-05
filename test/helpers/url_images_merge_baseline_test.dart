import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/helpers/message_url_image_helper.dart';

const _cid = 'bafybeibq75ws6nwk6wi473dch42wwy6woyj4dwdfy7nfz3buqx2caieoly';

void main() {
  final startupPolicy = MessageUrlImageHelper.loadLinkImages.value;
  late List<Uri> requests;
  late MockClient client;
  late bool previousPolicy;
  late Future<http.Response> Function(http.Request) respond;

  setUp(() {
    previousPolicy = MessageUrlImageHelper.loadLinkImages.value;
    // Parsing cases explicitly simulate a user who enabled URL downloads.
    MessageUrlImageHelper.loadLinkImages.value = true;
    requests = [];
    respond = (_) async => throw StateError('Unexpected sharing-page request');
    client = MockClient((request) {
      requests.add(request.url);
      return respond(request);
    });
    MessageUrlImageHelper.httpClient = client;
  });

  tearDown(() {
    MessageUrlImageHelper.loadLinkImages.value = previousPolicy;
    MessageUrlImageHelper.httpClient = null;
    client.close();
  });

  test('URL loading starts disabled before app settings are applied', () {
    expect(startupPolicy, isFalse);
  });

  test('U08 baseline: detecting every supported link stays entirely local', () {
    for (final text in [
      'https://example.com/photo.PNG?size=large',
      'https://pyx.li/?i=RzmdkTsE',
      'https://ibb.co/example',
      'ipfs://$_cid',
      'https://gateway.example/ipfs/$_cid',
    ]) {
      expect(MessageUrlImageHelper.hasPotentialImageUrl(text), isTrue,
          reason: text);
    }
    expect(MessageUrlImageHelper.hasPotentialImageUrl('plain text'), isFalse);
    expect(requests, isEmpty);
  });

  test('U08 baseline: direct links and CIDs retain their URLs without HTTP', () async {
    final corpus = <String, String>{
      'hello https://example.com/photo.png?size=large text':
          'https://example.com/photo.png?size=large',
      'https://example.com/photo.webp.': 'https://example.com/photo.webp',
      'https://pyx.li/?i=RzmdkTsE': 'https://pyx.li/i/RzmdkTsE.jpg',
      'ipfs://$_cid': 'https://ipfs.io/ipfs/$_cid',
      'ipfs:$_cid': 'https://ipfs.io/ipfs/$_cid',
      'https://chosen.example/ipfs/$_cid,': 'https://chosen.example/ipfs/$_cid',
      'https://chosen.example/ipns/example-name':
          'https://chosen.example/ipns/example-name',
    };
    for (final entry in corpus.entries) {
      expect(await MessageUrlImageHelper.parse(entry.key), entry.value,
          reason: entry.key);
    }
    expect(await MessageUrlImageHelper.parse('  '), isNull);
    expect(await MessageUrlImageHelper.parse('plain text'), isNull);
    expect(requests, isEmpty);
  });

  test('U08 baseline: sharing page resolves a relative image with one GET', () async {
    respond = (request) async {
      expect(request.method, 'GET');
      return http.Response(
        '<meta property="og:image" content="/photo.png?a=1&amp;b=2">',
        200,
      );
    };
    expect(
      await MessageUrlImageHelper.parse('https://ibb.co/example'),
      'https://ibb.co/photo.png?a=1&b=2',
    );
    expect(requests.map((uri) => uri.toString()), ['https://ibb.co/example']);
  });

  test('U08 baseline: page failure and unsafe image scheme stay hidden', () async {
    respond = (_) async => http.Response('unavailable', 503);
    expect(await MessageUrlImageHelper.parse('https://ibb.co/failure'), isNull);
    respond = (_) async => http.Response(
      '<meta property="og:image" content="file:///private/photo.png">',
      200,
    );
    expect(await MessageUrlImageHelper.parse('https://ibb.co/unsafe'), isNull);
    respond = (_) async => throw http.ClientException('synthetic offline');
    expect(await MessageUrlImageHelper.parse('https://ibb.co/offline'), isNull);
    // No implicit retry loop or additional image fetch during URL parsing.
    expect(requests, hasLength(3));
  });
}
