import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Your GitHub OAuth App client_id.
// Create one at https://github.com/settings/developers → OAuth Apps → New OAuth App
// Enable Device Flow in the app settings.
// The client_id is PUBLIC — safe to embed. No client_secret needed for Device Flow.
const githubClientId = 'Ov23li7o2lO8F65UIclz';

/// A GitHub account that can own repos — the signed-in user or an org.
class GitHubOwner {
  final String login;
  final String avatarUrl;
  final bool isUser;
  const GitHubOwner({
    required this.login,
    required this.avatarUrl,
    required this.isUser,
  });
}

/// A GitHub repository.
class GitHubRepo {
  final String name;
  final String fullName; // owner/name
  final String cloneUrl;
  final bool isPrivate;
  final String defaultBranch;
  final String? description;
  const GitHubRepo({
    required this.name,
    required this.fullName,
    required this.cloneUrl,
    required this.isPrivate,
    required this.defaultBranch,
    this.description,
  });
}

class DeviceCodeResponse {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;

  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  factory DeviceCodeResponse.fromJson(Map<String, dynamic> j) =>
      DeviceCodeResponse(
        deviceCode: j['device_code'] as String,
        userCode: j['user_code'] as String,
        verificationUri: j['verification_uri'] as String,
        expiresIn: j['expires_in'] as int,
        interval: j['interval'] as int,
      );
}

class GitHubDeviceAuth {
  /// Step 1 — request a device code from GitHub.
  /// Returns the code pair the user must enter at github.com/login/device
  Future<DeviceCodeResponse> requestDeviceCode() async {
    final res = await http.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'client_id': githubClientId,
        // read:org is required to list org memberships (so granted orgs show
        // up in the picker). repo = full repo access, user = profile.
        'scope': 'repo read:org user',
      }),
    );

    if (res.statusCode != 200) {
      throw Exception('GitHub device code request failed: ${res.statusCode}');
    }

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json.containsKey('error')) {
      throw Exception('GitHub error: ${json['error_description'] ?? json['error']}');
    }

    return DeviceCodeResponse.fromJson(json);
  }

  /// Step 2 — open github.com/login/device in the external browser (Chrome).
  Future<void> openVerificationUrl(String uri) async {
    final url = Uri.parse(uri);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  /// Step 3 — poll until the user approves (or it expires / errors).
  /// Calls [onWaiting] on each pending poll so the UI can update.
  Future<String> pollForToken(
    DeviceCodeResponse deviceCode, {
    void Function()? onWaiting,
  }) async {
    final deadline =
        DateTime.now().add(Duration(seconds: deviceCode.expiresIn));
    var pollInterval = Duration(seconds: deviceCode.interval);

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);

      final res = await http.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'client_id': githubClientId,
          'device_code': deviceCode.deviceCode,
          'grant_type':
              'urn:ietf:params:oauth:grant-type:device_code',
        }),
      );

      final json =
          jsonDecode(res.body) as Map<String, dynamic>;
      final error = json['error'] as String?;

      switch (error) {
        case null:
          // Success
          final token = json['access_token'] as String?;
          if (token != null && token.isNotEmpty) return token;
          throw Exception('No access_token in response');

        case 'authorization_pending':
          // User hasn't approved yet — keep polling
          onWaiting?.call();
          continue;

        case 'slow_down':
          // GitHub asks us to slow down
          pollInterval += const Duration(seconds: 5);
          onWaiting?.call();
          continue;

        case 'expired_token':
          throw Exception(
              'Device code expired. Please try again.');

        case 'access_denied':
          throw Exception('Access denied by user.');

        default:
          throw Exception(
              'GitHub error: ${json['error_description'] ?? error}');
      }
    }

    throw Exception('Device code expired. Please try again.');
  }
}

class GitHubApi {
  final String token;
  const GitHubApi(this.token);

  Future<Map<String, dynamic>> getCurrentUser() async {
    final res = await http.get(
      Uri.https('api.github.com', '/user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('GitHub API error ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// The signed-in user as an "owner" (login + avatar), plus their orgs.
  /// The personal account is always first so the UI can show it as a section.
  Future<List<GitHubOwner>> getOwners() async {
    final user = await getCurrentUser();
    final owners = <GitHubOwner>[
      GitHubOwner(
        login: user['login'] as String,
        avatarUrl: user['avatar_url'] as String? ?? '',
        isUser: true,
      ),
    ];

    // Collect orgs from BOTH endpoints and merge (deduped by login):
    //  - /user/orgs               → orgs with public membership / app-approved
    //  - /user/memberships/orgs   → ALL orgs you belong to (incl. private
    //                               membership), which /user/orgs can omit.
    // Some granted orgs only surface via the memberships endpoint, so querying
    // both is what makes every accessible org appear in the picker.
    final seen = <String>{};

    Future<void> addFrom(Uri uri, {required bool fromMemberships}) async {
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      });
      if (res.statusCode != 200) return;
      final list = jsonDecode(res.body) as List<dynamic>;
      for (final o in list) {
        final m = o as Map<String, dynamic>;
        // memberships endpoint nests the org under "organization"
        final org = fromMemberships
            ? (m['organization'] as Map<String, dynamic>?)
            : m;
        if (org == null) continue;
        final login = org['login'] as String?;
        if (login == null || !seen.add(login)) continue;
        owners.add(GitHubOwner(
          login: login,
          avatarUrl: org['avatar_url'] as String? ?? '',
          isUser: false,
        ));
      }
    }

    await addFrom(
      Uri.https('api.github.com', '/user/orgs', {'per_page': '100'}),
      fromMemberships: false,
    );
    await addFrom(
      Uri.https('api.github.com', '/user/memberships/orgs',
          {'per_page': '100', 'state': 'active'}),
      fromMemberships: true,
    );

    return owners;
  }

  /// Repos for an owner. For the signed-in user we use /user/repos (includes
  /// private); for an org we use /orgs/{org}/repos.
  Future<List<GitHubRepo>> getRepos(GitHubOwner owner) async {
    final uri = owner.isUser
        ? Uri.https('api.github.com', '/user/repos',
            {'per_page': '100', 'sort': 'updated', 'affiliation': 'owner'})
        : Uri.https('api.github.com', '/orgs/${owner.login}/repos',
            {'per_page': '100', 'sort': 'updated'});

    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github.v3+json',
    });
    if (res.statusCode != 200) {
      throw Exception('GitHub API error ${res.statusCode}: ${res.body}');
    }
    final list = jsonDecode(res.body) as List<dynamic>;
    return list.map((r) {
      final m = r as Map<String, dynamic>;
      return GitHubRepo(
        name: m['name'] as String,
        fullName: m['full_name'] as String,
        cloneUrl: m['clone_url'] as String,
        isPrivate: m['private'] as bool? ?? false,
        defaultBranch: m['default_branch'] as String? ?? 'main',
        description: m['description'] as String?,
      );
    }).toList();
  }

  Future<Map<String, dynamic>> createPr({
    required String repoUrl,
    required String title,
    required String body,
    required String head,
    required String base,
  }) async {
    final (owner, repo) = _parseRepo(repoUrl);
    final res = await http.post(
      Uri.https('api.github.com', '/repos/$owner/$repo/pulls'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'title': title,
        'body': body,
        'head': head,
        'base': base,
      }),
    );
    if (res.statusCode != 201) {
      throw Exception(
          'GitHub API error ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listPullRequests(
    String repoUrl, {
    String state = 'open',
  }) async {
    final (owner, repo) = _parseRepo(repoUrl);
    final res = await http.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/pulls', {
        'state': state,
        'per_page': '50',
        'sort': 'updated',
        'direction': 'desc',
      }),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );
    if (res.statusCode >= 400) {
      throw Exception('GitHub API error ${res.statusCode}: ${res.body}');
    }
    return (jsonDecode(res.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getPullRequest(
    String repoUrl,
    int number,
  ) async {
    final (owner, repo) = _parseRepo(repoUrl);
    final res = await http.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/pulls/$number'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );
    if (res.statusCode >= 400) {
      throw Exception('GitHub API error ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getPullRequestFiles(
    String repoUrl,
    int number,
  ) async {
    final (owner, repo) = _parseRepo(repoUrl);
    final res = await http.get(
      Uri.https(
        'api.github.com',
        '/repos/$owner/$repo/pulls/$number/files',
        {'per_page': '100'},
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
      },
    );
    if (res.statusCode >= 400) {
      throw Exception('GitHub API error ${res.statusCode}: ${res.body}');
    }
    return (jsonDecode(res.body) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getCombinedStatus(
    String repoUrl,
    String ref,
  ) async {
    try {
      final (owner, repo) = _parseRepo(repoUrl);
      final res = await http.get(
        Uri.https(
            'api.github.com', '/repos/$owner/$repo/commits/$ref/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github.v3+json',
        },
      );
      if (res.statusCode >= 400) return {'state': 'unknown'};
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {'state': 'unknown'};
    }
  }

  Future<Map<String, dynamic>> mergePullRequest(
    String repoUrl,
    int number, {
    String method = 'merge',
  }) async {
    final (owner, repo) = _parseRepo(repoUrl);
    final res = await http.put(
      Uri.https(
          'api.github.com', '/repos/$owner/$repo/pulls/$number/merge'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'merge_method': method}),
    );
    if (res.statusCode >= 400) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final msg = body['message'] as String? ?? res.body;
      throw Exception(msg);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  (String, String) _parseRepo(String url) {
    final uri = Uri.parse(url);
    final parts = uri.pathSegments;
    if (parts.length < 2) {
      throw Exception('Invalid repo URL: $url');
    }
    return (parts[0], parts[1].replaceAll('.git', ''));
  }
}
