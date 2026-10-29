import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/services/github_release_check.dart';

final _installed = 'a' * 40;
final _released = 'b' * 40;

void main() {
  for (final entry in {'ahead': true, 'behind': false, 'identical': false}.entries) {
    test('compares ancestry for ${entry.key}, regardless of release name', () async {
      final requests = <Uri>[];
      final api = GitHubReleaseCheck(client: MockClient((request) async {
        requests.add(request.url);
        expect(request.url.host, 'api.github.com');
        if (request.url.path.endsWith('/latest')) {
          return http.Response(jsonEncode({
            'tag_name': 'release/any name', 'target_commitish': 'moving-branch',
            'draft': false, 'prerelease': false,
          }), 200);
        }
        if (request.url.pathSegments.contains('commits')) {
          expect(request.url.pathSegments.last, 'release/any name');
          return http.Response(jsonEncode({'sha': _released}), 200);
        }
        expect(request.url.pathSegments.last, '$_installed...$_released');
        return http.Response(jsonEncode({'status': entry.key}), 200);
      }));
      addTearDown(api.close);
      expect(await api.hasNewerRelease(_installed), entry.value);
      expect(requests, hasLength(3));
    });
  }

  test('identical SHA skips comparison; missing SHA never makes an HTTP request', () async {
    var calls = 0;
    final api = GitHubReleaseCheck(client: MockClient((request) async {
      calls++;
      return http.Response(jsonEncode(request.url.path.endsWith('/latest') ? {
        'tag_name': 'v1', 'draft': false, 'prerelease': false,
      } : {'sha': _installed}), 200);
    }));
    addTearDown(api.close);
    await expectLater(api.hasNewerRelease(''), throwsA(isA<UpdateCheckException>()
      .having((e) => e.reason, 'reason', UpdateCheckError.missingCommit)));
    expect(calls, 0);
    expect(await api.hasNewerRelease(_installed), isFalse);
    expect(calls, 2);
  });

  for (final scenario in ['diverged', 'unknown', 'rate', 'malformed', 'http', 'network']) {
    test('$scenario reports an error rather than no updates', () async {
      final api = GitHubReleaseCheck(client: MockClient((request) async {
        if (scenario == 'network') throw http.ClientException('Synthetic offline');
        if (scenario == 'rate') {
          return http.Response('{}', 403,
            headers: {'x-ratelimit-remaining': '0'});
        }
        if (scenario == 'malformed') return http.Response('{', 200);
        if (scenario == 'http') return http.Response('{}', 503);
        if (request.url.path.endsWith('/latest')) {
          return http.Response(jsonEncode({
            'tag_name': 'v1', 'draft': false, 'prerelease': false,
          }), 200);
        }
        if (request.url.pathSegments.contains('commits')) {
          return http.Response(jsonEncode({'sha': _released}), 200);
        }
        return scenario == 'unknown' ? http.Response('{}', 404) :
            http.Response('{"status":"diverged"}', 200);
      }));
      addTearDown(api.close);
      final expected = {
        'diverged': UpdateCheckError.diverged, 'unknown': UpdateCheckError.unknownCommit,
        'rate': UpdateCheckError.rateLimit, 'malformed': UpdateCheckError.invalidResponse,
        'http': UpdateCheckError.http, 'network': UpdateCheckError.network,
      }[scenario];
      await expectLater(api.hasNewerRelease(_installed), throwsA(isA<UpdateCheckException>()
        .having((e) => e.reason, 'reason', expected)));
    });
  }
}
