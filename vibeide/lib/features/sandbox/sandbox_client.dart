import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

class GitStatus {
  final String branch;
  final List<String> staged, modified, untracked;

  const GitStatus({
    required this.branch,
    required this.staged,
    required this.modified,
    required this.untracked,
  });

  factory GitStatus.fromJson(Map<String, dynamic> j) => GitStatus(
        branch: j['branch'] as String,
        staged: List<String>.from(j['staged'] as List? ?? []),
        modified: List<String>.from(j['modified'] as List? ?? []),
        untracked: List<String>.from(j['untracked'] as List? ?? []),
      );
}

class FileNode {
  final String name, path;
  final bool isDir;
  final List<FileNode> children;

  const FileNode({
    required this.name,
    required this.path,
    required this.isDir,
    this.children = const [],
  });

  factory FileNode.fromJson(Map<String, dynamic> j) => FileNode(
        name: j['name'] as String,
        path: j['path'] as String,
        isDir: j['isDir'] as bool,
        children: (j['children'] as List<dynamic>? ?? [])
            .map((c) => FileNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

class SandboxClient {
  final Dio _dio;

  SandboxClient({int port = 7700})
      : _dio = Dio(BaseOptions(
          baseUrl: 'http://127.0.0.1:$port',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 60),
          validateStatus: (status) => status != null && status < 500,
        ));

  Future<bool> waitForReady({int maxAttempts = 30}) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final r = await _dio.get<dynamic>('/health');
        if (r.statusCode == 200) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<FileNode> getTree(String path) async {
    final r = await _dio.get<dynamic>('/fs/tree',
        queryParameters: {'path': path});
    return FileNode.fromJson(r.data as Map<String, dynamic>);
  }

  Future<String> readFile(String path) async {
    final r = await _dio.get<String>('/fs/read',
        queryParameters: {'path': path},
        options: Options(responseType: ResponseType.plain));
    return r.data ?? '';
  }

  Future<void> writeFile(String path, String content) async {
    await _dio.post<dynamic>('/fs/write',
        data: {'path': path, 'content': content});
  }

  Future<void> deleteFile(String path) async {
    await _dio.post<dynamic>('/fs/delete', data: {'path': path});
  }

  Stream<Map<String, dynamic>> exec(
    String command,
    List<String> args, {
    String? cwd,
  }) async* {
    final r = await _dio.post<ResponseBody>(
      '/shell/exec',
      data: {
        'command': command,
        'args': args,
        if (cwd != null) 'cwd': cwd,
      },
      options: Options(responseType: ResponseType.stream),
    );
    await for (final chunk in r.data!.stream) {
      for (final line in utf8.decode(chunk).split('\n')) {
        if (line.startsWith('data: ')) {
          yield jsonDecode(line.substring(6)) as Map<String, dynamic>;
        }
      }
    }
  }

  /// Runs a command to completion, returning (exitCode, combinedOutput).
  /// [onLine] is called for each stdout/stderr line as it arrives.
  Future<(int, String)> execToCompletion(
    String command,
    List<String> args, {
    String? cwd,
    void Function(String line)? onLine,
  }) async {
    final out = StringBuffer();
    var exitCode = 0;
    await for (final ev in exec(command, args, cwd: cwd)) {
      final type = ev['type'] as String?;
      if (type == 'stdout' || type == 'stderr') {
        final data = (ev['data'] as String?) ?? '';
        out.write(data);
        onLine?.call(data.trimRight());
      } else if (type == 'exit') {
        exitCode = (ev['code'] as int?) ?? 0;
      }
    }
    return (exitCode, out.toString());
  }

  /// Ensures git is installed in the Alpine sandbox (it's not in minirootfs).
  /// Idempotent — apk is a no-op if git is already present.
  Future<void> ensureGit({void Function(String line)? onLine}) async {
    // Check first to avoid a network round-trip when git already exists.
    final (checkCode, checkOut) = await execToCompletion(
        '/bin/sh', ['-lc', 'command -v git || true']);
    debugPrint('[ensureGit] check exit=$checkCode out="${checkOut.trim()}"');
    if (checkOut.trim().isNotEmpty) return; // git already on PATH

    onLine?.call('Installing git (first run, ~15s)...');
    // apk's CDN fetch can hit transient "temporary error (try again later)"
    // on mobile networks. Retry a few times before giving up.
    String lastOutput = '';
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (attempt > 1) {
        onLine?.call('Network hiccup, retrying ($attempt/3)...');
        await Future.delayed(const Duration(seconds: 2));
      }
      // Run through a login shell so apk's helpers (wget, ssl_client) are on
      // PATH. --no-cache fetches a fresh index each run.
      final (code, output) = await execToCompletion(
        '/bin/sh',
        ['-lc', 'apk add --no-cache git'],
        onLine: (line) {
          debugPrint('[apk] $line');
          onLine?.call(line);
        },
      );
      lastOutput = output;
      debugPrint('[ensureGit] apk attempt $attempt exit=$code');
      if (code == 0) return; // success
    }
    throw Exception('apk add git failed after 3 attempts:\n$lastOutput');
  }

  Future<GitStatus> gitStatus(String dir) async {
    final r = await _dio.get<dynamic>('/git/status',
        queryParameters: {'dir': dir});
    return GitStatus.fromJson(r.data as Map<String, dynamic>);
  }

  Future<String> gitDiff(String dir, {String base = 'HEAD'}) async {
    final r = await _dio.get<String>('/git/diff',
        queryParameters: {'dir': dir, 'base': base},
        options: Options(responseType: ResponseType.plain));
    return r.data ?? '';
  }

  Future<String> gitLog(String dir) async {
    final r = await _dio.get<String>('/git/log',
        queryParameters: {'dir': dir},
        options: Options(responseType: ResponseType.plain));
    return r.data ?? '';
  }

  Stream<String> gitClone(String url, String dir, {String? token}) async* {
    final r = await _dio.post<ResponseBody>(
      '/git/clone',
      data: {'url': url, 'dir': dir, if (token != null) 'token': token},
      options: Options(responseType: ResponseType.stream),
    );
    // SSE events can split across network chunks — buffer until we see a
    // newline, then process complete lines only.
    var buffer = '';
    await for (final chunk in r.data!.stream) {
      buffer += utf8.decode(chunk);
      while (buffer.contains('\n')) {
        final i = buffer.indexOf('\n');
        final line = buffer.substring(0, i);
        buffer = buffer.substring(i + 1);
        if (!line.startsWith('data: ')) continue;
        try {
          final j = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          if (j.containsKey('progress')) yield j['progress'] as String;
          if (j.containsKey('error')) throw Exception(j['error']);
        } on FormatException {
          // Partial/garbled JSON — skip this line
        }
      }
    }
  }

  Future<void> gitCommit(String dir, String message,
      {List<String>? files}) async {
    await _dio.post<dynamic>('/git/commit', data: {
      'dir': dir,
      'message': message,
      if (files != null) 'files': files,
    });
  }

  Future<void> gitPush(String dir, String branch, {String? token}) async {
    await _dio.post<dynamic>('/git/push', data: {
      'dir': dir,
      'branch': branch,
      if (token != null) 'token': token,
    });
  }

  Future<void> gitCheckout(String dir, String branch,
      {bool create = false}) async {
    await _dio.post<dynamic>('/git/checkout',
        data: {'dir': dir, 'branch': branch, 'create': create});
  }

  /// Returns all branch names (local + remote-tracking, de-duplicated by short
  /// name). Remote branches like `origin/main` are stripped to `main` and
  /// merged with local ones so each name appears only once.
  Future<List<String>> gitBranches(String dir) async {
    final (_, out) = await execToCompletion(
      '/bin/sh',
      ['-lc', "git -C '${dir.replaceAll("'", "'\\''")}' branch -a --format='%(refname:short)'"],
    );
    final seen = <String>{};
    final result = <String>[];
    for (final raw in out.split('\n')) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      // Strip remote-tracking prefix, e.g. "origin/main" → "main",
      // but keep names like "remotes/origin/feature" → "feature".
      final short = name
          .replaceFirst(RegExp(r'^remotes/[^/]+/'), '')
          .replaceFirst(RegExp(r'^[^/]+/'), '');
      // Use original name if it has no slash (local branch).
      final canonical = name.contains('/') ? short : name;
      if (canonical.isNotEmpty && seen.add(canonical)) {
        result.add(canonical);
      }
    }
    return result;
  }

  /// Returns the current branch name (e.g. "main").
  Future<String> gitCurrentBranch(String dir) async {
    final (_, out) = await execToCompletion(
      '/bin/sh',
      ['-lc', "git -C '${dir.replaceAll("'", "'\\''")}' rev-parse --abbrev-ref HEAD"],
    );
    return out.trim();
  }

  /// Returns `git diff <base>...HEAD --stat` output (diff summary).
  Future<String> gitDiffStat(String dir, {String base = 'main'}) async {
    final (_, out) = await execToCompletion(
      '/bin/sh',
      ['-lc', "git -C '${dir.replaceAll("'", "'\\''")}' diff '${base.replaceAll("'", "'\\''")}...HEAD' --stat"],
    );
    return out.trim();
  }

  /// Returns the list of files changed between [base] and HEAD, combined with
  /// any uncommitted (staged + unstaged + untracked) changes. De-duplicated.
  Future<List<String>> gitChangedFiles(String dir, {String base = 'main'}) async {
    final q = dir.replaceAll("'", "''");
    final b = base.replaceAll("'", "''");
    final cmd =
        "git -C '$q' diff '$b...HEAD' --name-only ; "
        "git -C '$q' diff --name-only ; "
        "git -C '$q' diff --cached --name-only";
    final (_, out) = await execToCompletion('/bin/sh', ['-lc', cmd]);
    final seen = <String>{};
    final result = <String>[];
    for (final line in out.split('\n')) {
      final f = line.trim();
      if (f.isNotEmpty && seen.add(f)) result.add(f);
    }
    return result;
  }

  /// Returns the unified diff for a single file between [base] and working tree
  /// (if base is null) or between [base] and HEAD.
  Future<String> gitFileDiff(String dir, String file, {String? base}) async {
    final q = dir.replaceAll("'", "''");
    final f = file.replaceAll("'", "''");
    final String cmd;
    if (base != null) {
      final b = base.replaceAll("'", "''");
      cmd = "git -C '$q' diff '$b...HEAD' -- '$f'";
    } else {
      cmd = "git -C '$q' diff HEAD -- '$f'";
    }
    final (_, out) = await execToCompletion('/bin/sh', ['-lc', cmd]);
    return out;
  }

  // ─── Pull / Fetch / Merge helpers ────────────────────────────────────────

  /// Fetches all remotes. Injects [token] into the remote URL the same way
  /// gitClone / gitPush do (token replaces the password in the HTTPS URL).
  Future<(int, String)> gitFetch(String dir, {String? token}) async {
    final q = dir.replaceAll("'", "'\\''"  );
    final String cmd;
    if (token != null) {
      // Temporarily set remote URL with embedded token so fetch can auth.
      cmd = "cd '$q' && "
          "ORIG_URL=\$(git remote get-url origin 2>/dev/null || echo '') && "
          "AUTH_URL=\$(echo \"\$ORIG_URL\" | sed 's|https://|https://x-access-token:${token.replaceAll("'", "'\\''")}@|') && "
          "git remote set-url origin \"\$AUTH_URL\" && "
          "git fetch --all 2>&1; CODE=\$?; "
          "git remote set-url origin \"\$ORIG_URL\"; "
          "exit \$CODE";
    } else {
      cmd = "git -C '$q' fetch --all 2>&1";
    }
    return execToCompletion('/bin/sh', ['-lc', cmd]);
  }

  /// Pulls origin/<branch>. Returns (exitCode, combinedOutput).
  /// Callers should check for "CONFLICT" or "Automatic merge failed" in output
  /// to detect merge conflicts.
  Future<(int, String)> gitPull(String dir, String branch,
      {String? token}) async {
    final q = dir.replaceAll("'", "'\\''" );
    final b = branch.replaceAll("'", "'\\''" );
    final String cmd;
    if (token != null) {
      cmd = "cd '$q' && "
          "ORIG_URL=\$(git remote get-url origin 2>/dev/null || echo '') && "
          "AUTH_URL=\$(echo \"\$ORIG_URL\" | sed 's|https://|https://x-access-token:${token.replaceAll("'", "'\\''")}@|') && "
          "git remote set-url origin \"\$AUTH_URL\" && "
          "git pull origin '$b' 2>&1; CODE=\$?; "
          "git remote set-url origin \"\$ORIG_URL\"; "
          "exit \$CODE";
    } else {
      cmd = "git -C '$q' pull origin '$b' 2>&1";
    }
    return execToCompletion('/bin/sh', ['-lc', cmd]);
  }

  /// Merges [branch] into the current branch.
  Future<(int, String)> gitMerge(String dir, String branch) async {
    final q = dir.replaceAll("'", "'\\''" );
    final b = branch.replaceAll("'", "'\\''" );
    return execToCompletion(
        '/bin/sh', ['-lc', "git -C '$q' merge '$b' 2>&1"]);
  }

  /// Returns the list of files with unresolved merge conflicts
  /// (i.e., files in "unmerged" state).
  Future<List<String>> gitConflictedFiles(String dir) async {
    final q = dir.replaceAll("'", "'\\''" );
    final (_, out) = await execToCompletion(
      '/bin/sh',
      ['-lc', "git -C '$q' diff --name-only --diff-filter=U 2>&1"],
    );
    final result = <String>[];
    for (final line in out.split('\n')) {
      final f = line.trim();
      if (f.isNotEmpty) result.add(f);
    }
    return result;
  }

  /// Aborts an in-progress merge.
  Future<(int, String)> gitMergeAbort(String dir) async {
    final q = dir.replaceAll("'", "'\\''" );
    return execToCompletion(
        '/bin/sh', ['-lc', "git -C '$q' merge --abort 2>&1"]);
  }

  /// Stages the given [files] (relative paths from repo root).
  Future<(int, String)> gitAdd(String dir, List<String> files) async {
    final q = dir.replaceAll("'", "'\\''" );
    final quoted =
        files.map((f) => "'${f.replaceAll("'", "\\'")}'").join(' ');
    return execToCompletion(
        '/bin/sh', ['-lc', "git -C '$q' add $quoted 2>&1"]);
  }

  /// Completes a merge that has no more conflicts (equivalent to
  /// `git commit --no-edit`).
  Future<(int, String)> gitMergeContinue(String dir) async {
    final q = dir.replaceAll("'", "'\\''" );
    return execToCompletion(
        '/bin/sh', ['-lc', "git -C '$q' commit --no-edit 2>&1"]);
  }

  /// Returns true if a merge is currently in progress (MERGE_HEAD exists).
  Future<bool> gitMergeInProgress(String dir) async {
    final q = dir.replaceAll("'", "'\\''" );
    final (code, _) = await execToCompletion(
      '/bin/sh',
      ['-lc', "git -C '$q' rev-parse -q --verify MERGE_HEAD 2>/dev/null"],
    );
    return code == 0;
  }

  /// Returns how many commits the local branch is behind origin/<branch>.
  /// Returns 0 on any error (e.g., remote not fetched yet).
  Future<int> gitBehindCount(String dir, String branch) async {
    final q = dir.replaceAll("'", "'\\''" );
    final b = branch.replaceAll("'", "'\\''" );
    final (code, out) = await execToCompletion(
      '/bin/sh',
      ['-lc', "git -C '$q' rev-list --count '$b..origin/$b' 2>/dev/null"],
    );
    if (code != 0) return 0;
    return int.tryParse(out.trim()) ?? 0;
  }
}
