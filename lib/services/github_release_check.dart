import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

final githubReleasesPage = Uri.https('github.com', '/HDDen/meshcore-open/releases');

enum UpdateCheckError {
  missingCommit, unknownCommit, diverged, network, timeout, rateLimit,
  http, invalidResponse, storage, browser,
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.reason, {this.statusCode});
  final UpdateCheckError reason;
  final int? statusCode;
}

class GitHubReleaseCheck {
  GitHubReleaseCheck({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static final _sha = RegExp(r'^[0-9a-f]{40}$');
  static bool validCommit(String value) => _sha.hasMatch(value);

  Uri _uri(List<String> suffix, [Map<String, String>? query]) => Uri(
    scheme: 'https', host: 'api.github.com',
    pathSegments: ['repos', 'HDDen', 'meshcore-open', ...suffix],
    queryParameters: query,
  );

  Future<Map<String, dynamic>> _get(Uri uri, {bool comparing = false}) async {
    try {
      final response = await _client.get(uri, headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'MCOAdvanced-update-check',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 429 ||
          (response.statusCode == 403 && response.headers['x-ratelimit-remaining'] == '0')) {
        throw const UpdateCheckException(UpdateCheckError.rateLimit);
      }
      if (comparing && response.statusCode == 404) {
        throw const UpdateCheckException(UpdateCheckError.unknownCommit);
      }
      if (response.statusCode != 200) {
        throw UpdateCheckException(UpdateCheckError.http, statusCode: response.statusCode);
      }
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) {
        throw const UpdateCheckException(UpdateCheckError.invalidResponse);
      }
      return body;
    } on UpdateCheckException {
      rethrow;
    } on TimeoutException {
      throw const UpdateCheckException(UpdateCheckError.timeout);
    } on FormatException {
      throw const UpdateCheckException(UpdateCheckError.invalidResponse);
    } catch (_) {
      throw const UpdateCheckException(UpdateCheckError.network);
    }
  }

  /// Resolve the TAG, not target_commitish (which may be a moving branch).
  /// Versions and timestamps never decide whether a release is newer.
  Future<bool> hasNewerRelease(String installedCommit) async {
    if (!validCommit(installedCommit)) {
      throw const UpdateCheckException(UpdateCheckError.missingCommit);
    }
    final release = await _get(_uri(['releases', 'latest']));
    final tag = release['tag_name'];
    if (tag is! String || tag.trim().isEmpty ||
        release['draft'] != false || release['prerelease'] != false) {
      throw const UpdateCheckException(UpdateCheckError.invalidResponse);
    }
    final commit = await _get(_uri(['commits', tag]));
    final sha = commit['sha'];
    if (sha is! String || !validCommit(sha)) {
      throw const UpdateCheckException(UpdateCheckError.invalidResponse);
    }
    if (sha == installedCommit) return false;
    final comparison = await _get(
      _uri(['compare', '$installedCommit...$sha'], {'per_page': '1'}),
      comparing: true,
    );
    return switch (comparison['status']) {
      'ahead' => true,
      'identical' || 'behind' => false,
      'diverged' => throw const UpdateCheckException(UpdateCheckError.diverged),
      _ => throw const UpdateCheckException(UpdateCheckError.invalidResponse),
    };
  }

  void close() => _client.close();
}
