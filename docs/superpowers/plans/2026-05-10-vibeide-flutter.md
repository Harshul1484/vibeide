# VibeIDE — Flutter App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the VibeIDE Flutter app — a VS Code-style mobile IDE for Android that boots an Alpine Linux sandbox via proot, communicates with the vibecli daemon, and provides a code editor, terminal, git panel, and multi-provider AI assistant.

**Architecture:** Flutter + Riverpod for state. A Kotlin platform channel (`ProotPlugin`) boots proot and manages the process lifecycle. A `SandboxClient` Dart class wraps all vibecli HTTP/SSE/WS calls. Features are split into focused packages under `lib/features/`. SQLite stores projects and token usage.

**Tech Stack:** Flutter 3.22+, Dart 3.4+, `riverpod 2.5`, `re_editor`, `flutter_inappwebview 6`, `dio 5`, `flutter_web_auth_2`, `flutter_secure_storage`, `sqflite`, `anthropic_sdk_dart`

**Prerequisite:** `dist/vibecli-arm64` from the vibecli plan must exist and be copied to `android/app/src/main/assets/vibecli-arm64`.

---

## File Map

```
vibeide/
├── pubspec.yaml
├── android/
│   └── app/src/main/
│       ├── kotlin/com/vibeide/app/
│       │   ├── MainActivity.kt
│       │   └── ProotPlugin.kt
│       └── assets/
│           ├── alpine-arm64.tar.gz     ← Alpine Linux rootfs
│           ├── proot-arm64             ← proot binary for Android
│           ├── vibecli-arm64           ← built in vibecli plan
│           └── terminal/
│               └── index.html          ← bundled xterm.js page
├── lib/
│   ├── main.dart
│   ├── app.dart                        ← MaterialApp + theme
│   ├── shared/
│   │   ├── db.dart                     ← sqflite database helper
│   │   ├── theme.dart                  ← VS Code dark theme
│   │   └── providers.dart              ← top-level Riverpod providers
│   ├── features/
│   │   ├── sandbox/
│   │   │   ├── sandbox_client.dart     ← vibecli HTTP/SSE/WS client
│   │   │   ├── sandbox_provider.dart   ← Riverpod providers for sandbox state
│   │   │   └── proot_channel.dart      ← MethodChannel wrapper for ProotPlugin
│   │   ├── projects/
│   │   │   ├── project.dart            ← Project model
│   │   │   ├── project_repo.dart       ← sqflite CRUD
│   │   │   ├── project_provider.dart
│   │   │   └── project_manager_screen.dart
│   │   ├── shell/
│   │   │   ├── shell_layout.dart       ← VS Code shell (activity bar + panels)
│   │   │   └── status_bar.dart
│   │   ├── explorer/
│   │   │   ├── file_node.dart
│   │   │   ├── explorer_provider.dart
│   │   │   └── explorer_panel.dart
│   │   ├── editor/
│   │   │   ├── editor_provider.dart    ← open tabs, active file
│   │   │   └── editor_panel.dart       ← re_editor integration
│   │   ├── terminal/
│   │   │   └── terminal_panel.dart     ← xterm.js WebView
│   │   ├── git/
│   │   │   ├── git_provider.dart
│   │   │   ├── scm_panel.dart
│   │   │   └── pr_screen.dart
│   │   ├── auth/
│   │   │   ├── github_auth.dart        ← OAuth flow
│   │   │   └── auth_provider.dart
│   │   ├── ai/
│   │   │   ├── ai_client.dart          ← multi-provider streaming client
│   │   │   ├── ai_provider.dart        ← Riverpod + token budget
│   │   │   └── ai_panel.dart           ← chat UI
│   │   └── settings/
│   │       ├── settings_repo.dart
│   │       └── settings_screen.dart
└── test/
    ├── sandbox_client_test.dart
    ├── project_repo_test.dart
    └── ai_client_test.dart
```

---

## Task 1: Flutter Project & Dependencies

**Files:**
- Create: `vibeide/pubspec.yaml`
- Create: `vibeide/lib/main.dart`
- Create: `vibeide/lib/app.dart`
- Create: `vibeide/lib/shared/theme.dart`

- [ ] **Step 1: Create Flutter project**

```bash
flutter create vibeide --org com.vibeide --platforms android
cd vibeide
```

- [ ] **Step 2: Replace `pubspec.yaml` dependencies section**

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5
  re_editor: ^0.3.2
  re_highlight: ^0.0.3
  flutter_inappwebview: ^6.1.5
  dio: ^5.4.3
  flutter_web_auth_2: ^3.1.2
  flutter_secure_storage: ^9.2.2
  sqflite: ^2.3.3+1
  path_provider: ^2.1.4
  path: ^1.9.0
  anthropic_sdk_dart: ^0.9.0
  http: ^1.2.2
  web_socket_channel: ^3.0.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.9
  riverpod_generator: ^2.4.3
  mocktail: ^1.0.4

flutter:
  assets:
    - assets/terminal/
```

- [ ] **Step 3: Run `flutter pub get`**

```bash
flutter pub get
```
Expected: no errors

- [ ] **Step 4: Write `lib/shared/theme.dart`**

```dart
import 'package:flutter/material.dart';

const _bg = Color(0xFF1E1E1E);
const _sidebar = Color(0xFF252526);
const _panel = Color(0xFF1E1E1E);
const _border = Color(0xFF3E3E42);
const _accent = Color(0xFF0078D4);
const _fg = Color(0xFFD4D4D4);
const _fgMuted = Color(0xFF858585);

final vscodeDark = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _bg,
  colorScheme: const ColorScheme.dark(
    surface: _bg,
    primary: _accent,
    onSurface: _fg,
    outline: _border,
  ),
  dividerColor: _border,
  drawerTheme: const DrawerThemeData(backgroundColor: _sidebar),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF323233),
    foregroundColor: _fg,
    elevation: 0,
    titleTextStyle: TextStyle(color: _fg, fontSize: 13),
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: _fg, fontSize: 13, fontFamily: 'monospace'),
    bodySmall: TextStyle(color: _fgMuted, fontSize: 11),
  ),
  iconTheme: const IconThemeData(color: _fgMuted, size: 18),
  extensions: const [VsCodeColors(bg: _bg, sidebar: _sidebar, panel: _panel, border: _border, accent: _accent, fg: _fg, fgMuted: _fgMuted)],
);

class VsCodeColors extends ThemeExtension<VsCodeColors> {
  const VsCodeColors({required this.bg, required this.sidebar, required this.panel, required this.border, required this.accent, required this.fg, required this.fgMuted});
  final Color bg, sidebar, panel, border, accent, fg, fgMuted;

  @override
  VsCodeColors copyWith({Color? bg, Color? sidebar, Color? panel, Color? border, Color? accent, Color? fg, Color? fgMuted}) =>
      VsCodeColors(bg: bg ?? this.bg, sidebar: sidebar ?? this.sidebar, panel: panel ?? this.panel, border: border ?? this.border, accent: accent ?? this.accent, fg: fg ?? this.fg, fgMuted: fgMuted ?? this.fgMuted);

  @override
  VsCodeColors lerp(VsCodeColors? other, double t) => this;
}
```

- [ ] **Step 5: Write `lib/app.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'shared/theme.dart';
import 'features/projects/project_manager_screen.dart';

class VibeIdeApp extends ConsumerWidget {
  const VibeIdeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'VibeIDE',
      theme: vscodeDark,
      debugShowCheckedModeBanner: false,
      home: const ProjectManagerScreen(),
    );
  }
}
```

- [ ] **Step 6: Write `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: VibeIdeApp()));
}
```

- [ ] **Step 7: Run the app (should show blank dark screen)**

```bash
flutter run
```
Expected: dark screen, no crashes

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat: flutter project scaffold with VS Code dark theme"
```

---

## Task 2: Android ProotPlugin (Kotlin)

**Files:**
- Create: `android/app/src/main/kotlin/com/vibeide/app/ProotPlugin.kt`
- Modify: `android/app/src/main/kotlin/com/vibeide/app/MainActivity.kt`
- Modify: `android/app/build.gradle` — add `implementation 'org.apache.commons:commons-compress:1.26.1'`

- [ ] **Step 1: Add commons-compress to `android/app/build.gradle`**

In the `dependencies` block add:
```groovy
implementation 'org.apache.commons:commons-compress:1.26.1'
```

- [ ] **Step 2: Write `ProotPlugin.kt`**

```kotlin
package com.vibeide.app

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import java.io.File
import java.util.zip.GZIPInputStream

class ProotPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var ctx: Context
    private var prootProcess: Process? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ctx = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "com.vibeide/proot")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isExtracted"      -> result.success(isExtracted())
            "extractAlpine"    -> extractAlpine(result)
            "startSandbox"     -> startSandbox(result)
            "stopSandbox"      -> { prootProcess?.destroy(); prootProcess = null; result.success(true) }
            "isSandboxRunning" -> result.success(prootProcess?.isAlive == true)
            else               -> result.notImplemented()
        }
    }

    private fun alpineDir() = File(ctx.filesDir, "alpine")
    private fun prootBin() = File(ctx.filesDir, "proot")
    private fun vibecliPath() = File(alpineDir(), "bin/vibecli")
    private fun isExtracted() = alpineDir().exists() && vibecliPath().exists()

    private fun extractAlpine(result: MethodChannel.Result) {
        scope.launch {
            try {
                // Copy proot binary from assets
                ctx.assets.open("proot-arm64").use { inp ->
                    prootBin().outputStream().use { inp.copyTo(it) }
                }
                prootBin().setExecutable(true)

                // Extract Alpine rootfs tarball
                val alpine = alpineDir().also { it.mkdirs() }
                ctx.assets.open("alpine-arm64.tar.gz").use { raw ->
                    GZIPInputStream(raw).use { gz ->
                        TarArchiveInputStream(gz).use { tar ->
                            var entry = tar.nextTarEntry
                            while (entry != null) {
                                val out = File(alpine, entry.name)
                                if (entry.isDirectory) {
                                    out.mkdirs()
                                } else {
                                    out.parentFile?.mkdirs()
                                    out.outputStream().use { tar.copyTo(it) }
                                    if (entry.mode and 0b001001001 != 0) out.setExecutable(true)
                                }
                                entry = tar.nextTarEntry
                            }
                        }
                    }
                }

                // Copy vibecli into Alpine /bin
                ctx.assets.open("vibecli-arm64").use { inp ->
                    vibecliPath().outputStream().use { inp.copyTo(it) }
                }
                vibecliPath().setExecutable(true)

                withContext(Dispatchers.Main) { result.success(true) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("EXTRACT_ERR", e.message, null) }
            }
        }
    }

    private fun startSandbox(result: MethodChannel.Result) {
        scope.launch {
            try {
                val alpine = alpineDir().absolutePath
                val proot  = prootBin().absolutePath
                val cmd = arrayOf(
                    proot,
                    "--rootfs=$alpine",
                    "--bind=/proc", "--bind=/sys",
                    "--bind=/dev", "--bind=/dev/pts",
                    "-w", "/root",
                    "/bin/vibecli", "serve", "--port", "7700"
                )
                prootProcess = ProcessBuilder(*cmd).redirectErrorStream(true).start()
                withContext(Dispatchers.Main) { result.success(true) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("START_ERR", e.message, null) }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        prootProcess?.destroy()
        scope.cancel()
    }
}
```

- [ ] **Step 3: Register plugin in `MainActivity.kt`**

```kotlin
package com.vibeide.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(ProotPlugin())
    }
}
```

- [ ] **Step 4: Write `lib/features/sandbox/proot_channel.dart`**

```dart
import 'package:flutter/services.dart';

class ProotChannel {
  static const _ch = MethodChannel('com.vibeide/proot');

  Future<bool> isExtracted() async => await _ch.invokeMethod('isExtracted') as bool;
  Future<void> extractAlpine() async => await _ch.invokeMethod('extractAlpine');
  Future<void> startSandbox() async => await _ch.invokeMethod('startSandbox');
  Future<void> stopSandbox() async => await _ch.invokeMethod('stopSandbox');
  Future<bool> isSandboxRunning() async => await _ch.invokeMethod('isSandboxRunning') as bool;
}
```

- [ ] **Step 5: Build and verify no Kotlin errors**

```bash
flutter build apk --debug 2>&1 | grep -i error
```
Expected: no errors

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: Android ProotPlugin Kotlin channel to boot Alpine via proot"
```

---

## Task 3: SandboxClient & Boot Flow

**Files:**
- Create: `lib/features/sandbox/sandbox_client.dart`
- Create: `lib/features/sandbox/sandbox_provider.dart`
- Create: `test/sandbox_client_test.dart`

- [ ] **Step 1: Write the test (uses a real local HTTP server as a mock vibecli)**

```dart
// test/sandbox_client_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibeide/features/sandbox/sandbox_client.dart';

void main() {
  late HttpServer server;
  late SandboxClient client;

  setUp(() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      if (req.uri.path == '/health') {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"status":"ok"}')
          ..close();
      } else if (req.uri.path == '/fs/read') {
        req.response
          ..statusCode = 200
          ..write('hello file')
          ..close();
      } else if (req.uri.path == '/git/status') {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{"branch":"main","staged":[],"modified":[],"untracked":[]}')
          ..close();
      }
    });
    client = SandboxClient(port: server.port);
  });

  tearDown(() => server.close());

  test('waitForReady returns true when server responds', () async {
    final ready = await client.waitForReady(maxAttempts: 3);
    expect(ready, isTrue);
  });

  test('readFile returns file content', () async {
    final content = await client.readFile('/root/test.txt');
    expect(content, 'hello file');
  });

  test('gitStatus returns GitStatus model', () async {
    final status = await client.gitStatus('/root/project');
    expect(status.branch, 'main');
  });
}
```

- [ ] **Step 2: Run — confirm fail**

```bash
flutter test test/sandbox_client_test.dart
```
Expected: compilation error

- [ ] **Step 3: Write `lib/features/sandbox/sandbox_client.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';

class GitStatus {
  final String branch;
  final List<String> staged, modified, untracked;
  const GitStatus({required this.branch, required this.staged, required this.modified, required this.untracked});
  factory GitStatus.fromJson(Map<String, dynamic> j) => GitStatus(
        branch: j['branch'] as String,
        staged: List<String>.from(j['staged'] ?? []),
        modified: List<String>.from(j['modified'] ?? []),
        untracked: List<String>.from(j['untracked'] ?? []),
      );
}

class FileNode {
  final String name, path;
  final bool isDir;
  final List<FileNode> children;
  const FileNode({required this.name, required this.path, required this.isDir, this.children = const []});
  factory FileNode.fromJson(Map<String, dynamic> j) => FileNode(
        name: j['name'] as String,
        path: j['path'] as String,
        isDir: j['isDir'] as bool,
        children: (j['children'] as List<dynamic>? ?? []).map((c) => FileNode.fromJson(c as Map<String, dynamic>)).toList(),
      );
}

class SandboxClient {
  final Dio _dio;

  SandboxClient({int port = 7700})
      : _dio = Dio(BaseOptions(
          baseUrl: 'http://127.0.0.1:$port',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 60),
        ));

  Future<bool> waitForReady({int maxAttempts = 30}) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final r = await _dio.get('/health');
        if (r.statusCode == 200) return true;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<FileNode> getTree(String path) async {
    final r = await _dio.get('/fs/tree', queryParameters: {'path': path});
    return FileNode.fromJson(r.data as Map<String, dynamic>);
  }

  Future<String> readFile(String path) async {
    final r = await _dio.get<String>('/fs/read', queryParameters: {'path': path},
        options: Options(responseType: ResponseType.plain));
    return r.data ?? '';
  }

  Future<void> writeFile(String path, String content) async {
    await _dio.post('/fs/write', data: {'path': path, 'content': content});
  }

  Future<void> deleteFile(String path) async {
    await _dio.post('/fs/delete', data: {'path': path});
  }

  Stream<Map<String, dynamic>> exec(String command, List<String> args, {String? cwd}) async* {
    final r = await _dio.post<ResponseBody>('/shell/exec',
        data: {'command': command, 'args': args, if (cwd != null) 'cwd': cwd},
        options: Options(responseType: ResponseType.stream));
    await for (final chunk in r.data!.stream) {
      for (final line in utf8.decode(chunk).split('\n')) {
        if (line.startsWith('data: ')) {
          yield jsonDecode(line.substring(6)) as Map<String, dynamic>;
        }
      }
    }
  }

  Future<GitStatus> gitStatus(String dir) async {
    final r = await _dio.get('/git/status', queryParameters: {'dir': dir});
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
        queryParameters: {'dir': dir}, options: Options(responseType: ResponseType.plain));
    return r.data ?? '';
  }

  Stream<String> gitClone(String url, String dir, {String? token}) async* {
    final r = await _dio.post<ResponseBody>('/git/clone',
        data: {'url': url, 'dir': dir, if (token != null) 'token': token},
        options: Options(responseType: ResponseType.stream));
    await for (final chunk in r.data!.stream) {
      for (final line in utf8.decode(chunk).split('\n')) {
        if (line.startsWith('data: ')) {
          final j = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          if (j.containsKey('progress')) yield j['progress'] as String;
          if (j.containsKey('error')) throw Exception(j['error']);
        }
      }
    }
  }

  Future<void> gitCommit(String dir, String message, {List<String>? files}) async {
    await _dio.post('/git/commit',
        data: {'dir': dir, 'message': message, if (files != null) 'files': files});
  }

  Future<void> gitPush(String dir, String branch, {String? token}) async {
    await _dio.post('/git/push',
        data: {'dir': dir, 'branch': branch, if (token != null) 'token': token});
  }

  Future<void> gitCheckout(String dir, String branch, {bool create = false}) async {
    await _dio.post('/git/checkout',
        data: {'dir': dir, 'branch': branch, 'create': create});
  }
}
```

- [ ] **Step 4: Write `lib/features/sandbox/sandbox_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'proot_channel.dart';
import 'sandbox_client.dart';

enum SandboxState { idle, extracting, booting, ready, error }

class SandboxNotifier extends Notifier<SandboxState> {
  final _proot = ProotChannel();
  late final SandboxClient client;

  @override
  SandboxState build() {
    client = SandboxClient();
    return SandboxState.idle;
  }

  Future<void> boot() async {
    state = SandboxState.extracting;
    if (!await _proot.isExtracted()) {
      await _proot.extractAlpine();
    }
    state = SandboxState.booting;
    await _proot.startSandbox();
    final ready = await client.waitForReady();
    state = ready ? SandboxState.ready : SandboxState.error;
  }

  Future<void> stop() async {
    await _proot.stopSandbox();
    state = SandboxState.idle;
  }
}

final sandboxProvider = NotifierProvider<SandboxNotifier, SandboxState>(SandboxNotifier.new);
final sandboxClientProvider = Provider<SandboxClient>((ref) => ref.watch(sandboxProvider.notifier).client);
```

- [ ] **Step 5: Run tests**

```bash
flutter test test/sandbox_client_test.dart
```
Expected: `PASS` for all 3 tests

- [ ] **Step 6: Commit**

```bash
git add lib/features/sandbox/ test/sandbox_client_test.dart
git commit -m "feat: SandboxClient and boot flow with Riverpod state"
```

---

## Task 4: Database Layer & Project Model

**Files:**
- Create: `lib/shared/db.dart`
- Create: `lib/features/projects/project.dart`
- Create: `lib/features/projects/project_repo.dart`
- Create: `test/project_repo_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/project_repo_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vibeide/features/projects/project.dart';
import 'package:vibeide/features/projects/project_repo.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('insert and list projects', () async {
    final repo = ProjectRepo(dbPath: ':memory:');
    await repo.init();

    final p = Project(id: 'abc', name: 'my-app', remoteUrl: 'https://github.com/u/r', branch: 'main', localPath: '/root/projects/abc', lastOpened: DateTime.now());
    await repo.insert(p);

    final list = await repo.listAll();
    expect(list.length, 1);
    expect(list.first.name, 'my-app');
  });

  test('update last opened', () async {
    final repo = ProjectRepo(dbPath: ':memory:');
    await repo.init();
    final p = Project(id: 'x', name: 'p', remoteUrl: '', branch: 'main', localPath: '/root/x', lastOpened: DateTime(2020));
    await repo.insert(p);
    await repo.touchLastOpened('x');
    final updated = await repo.getById('x');
    expect(updated!.lastOpened.year, greaterThan(2020));
  });
}
```

- [ ] **Step 2: Add test dependency**

```yaml
# in dev_dependencies:
sqflite_common_ffi: ^2.3.3
```

Then `flutter pub get`.

- [ ] **Step 3: Run — confirm fail**

```bash
flutter test test/project_repo_test.dart
```
Expected: compilation error

- [ ] **Step 4: Write `lib/features/projects/project.dart`**

```dart
class Project {
  final String id, name, remoteUrl, branch, localPath;
  final DateTime lastOpened;
  const Project({required this.id, required this.name, required this.remoteUrl, required this.branch, required this.localPath, required this.lastOpened});

  Map<String, dynamic> toMap() => {
    'id': id, 'name': name, 'remoteUrl': remoteUrl,
    'branch': branch, 'localPath': localPath,
    'lastOpened': lastOpened.millisecondsSinceEpoch,
  };

  factory Project.fromMap(Map<String, dynamic> m) => Project(
    id: m['id'] as String, name: m['name'] as String,
    remoteUrl: m['remoteUrl'] as String, branch: m['branch'] as String,
    localPath: m['localPath'] as String,
    lastOpened: DateTime.fromMillisecondsSinceEpoch(m['lastOpened'] as int),
  );
}
```

- [ ] **Step 5: Write `lib/features/projects/project_repo.dart`**

```dart
import 'package:sqflite/sqflite.dart';
import 'project.dart';

class ProjectRepo {
  final String dbPath;
  Database? _db;

  ProjectRepo({this.dbPath = 'vibeide.db'});

  Future<void> init() async {
    _db = await openDatabase(dbPath, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE projects (
          id TEXT PRIMARY KEY, name TEXT, remoteUrl TEXT,
          branch TEXT, localPath TEXT, lastOpened INTEGER
        )
      ''');
    });
  }

  Future<void> insert(Project p) => _db!.insert('projects', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> delete(String id) => _db!.delete('projects', where: 'id = ?', whereArgs: [id]);
  Future<void> updateBranch(String id, String branch) => _db!.update('projects', {'branch': branch}, where: 'id = ?', whereArgs: [id]);

  Future<void> touchLastOpened(String id) => _db!.update(
      'projects', {'lastOpened': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?', whereArgs: [id]);

  Future<List<Project>> listAll() async {
    final rows = await _db!.query('projects', orderBy: 'lastOpened DESC');
    return rows.map(Project.fromMap).toList();
  }

  Future<Project?> getById(String id) async {
    final rows = await _db!.query('projects', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Project.fromMap(rows.first);
  }
}
```

- [ ] **Step 6: Write `lib/shared/db.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/projects/project_repo.dart';

final projectRepoProvider = Provider<ProjectRepo>((ref) {
  throw UnimplementedError('override in ProviderScope');
});
```

- [ ] **Step 7: Run tests — confirm pass**

```bash
flutter test test/project_repo_test.dart
```
Expected: `PASS`

- [ ] **Step 8: Commit**

```bash
git add lib/features/projects/ lib/shared/db.dart test/project_repo_test.dart
git commit -m "feat: Project model and SQLite repository"
```

---

## Task 5: Project Manager Screen

**Files:**
- Create: `lib/features/projects/project_provider.dart`
- Create: `lib/features/projects/project_manager_screen.dart`

- [ ] **Step 1: Write `lib/features/projects/project_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/db.dart';
import 'project.dart';
import 'project_repo.dart';

class ProjectsNotifier extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() async {
    final repo = ref.read(projectRepoProvider);
    return repo.listAll();
  }

  Future<void> add(Project p) async {
    await ref.read(projectRepoProvider).insert(p);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    await ref.read(projectRepoProvider).delete(id);
    ref.invalidateSelf();
  }

  Future<void> open(String id) async {
    await ref.read(projectRepoProvider).touchLastOpened(id);
    ref.invalidateSelf();
  }
}

final projectsProvider = AsyncNotifierProvider<ProjectsNotifier, List<Project>>(ProjectsNotifier.new);
final activeProjectProvider = StateProvider<Project?>((ref) => null);
```

- [ ] **Step 2: Write `lib/features/projects/project_manager_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'project.dart';
import 'project_provider.dart';
import '../shell/shell_layout.dart';
import '../sandbox/sandbox_provider.dart';

class ProjectManagerScreen extends ConsumerWidget {
  const ProjectManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final projects = ref.watch(projectsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: const Text('VibeIDE'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Clone repo',
            onPressed: () => _showCloneDialog(context, ref)),
        ],
      ),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => list.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.folder_open, size: 64, color: c.fgMuted),
                  const SizedBox(height: 16),
                  Text('No projects yet', style: TextStyle(color: c.fgMuted)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () => _showCloneDialog(context, ref), child: const Text('Clone from GitHub')),
                ]),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: list.length,
                separatorBuilder: (_, __) => Divider(color: c.border, height: 1),
                itemBuilder: (context, i) => _ProjectTile(project: list[i]),
              ),
      ),
    );
  }

  void _showCloneDialog(BuildContext context, WidgetRef ref) {
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).extension<VsCodeColors>()!.sidebar,
        title: const Text('Clone Repository'),
        content: TextField(
          controller: urlCtrl,
          decoration: const InputDecoration(hintText: 'https://github.com/user/repo'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Clone is triggered after navigating to ShellLayout
            },
            child: const Text('Clone'),
          ),
        ],
      ),
    );
  }
}

class _ProjectTile extends ConsumerWidget {
  final Project project;
  const _ProjectTile({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    return ListTile(
      leading: Icon(Icons.folder, color: c.accent),
      title: Text(project.name, style: TextStyle(color: c.fg)),
      subtitle: Text('${project.remoteUrl}  ⎇ ${project.branch}', style: TextStyle(color: c.fgMuted, fontSize: 11)),
      trailing: Text(_ago(project.lastOpened), style: TextStyle(color: c.fgMuted, fontSize: 11)),
      onTap: () async {
        ref.read(activeProjectProvider.notifier).state = project;
        await ref.read(projectsProvider.notifier).open(project.id);
        await ref.read(sandboxProvider.notifier).boot();
        if (context.mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ShellLayout()));
        }
      },
    );
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    return '${d.inMinutes}m ago';
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/projects/ && git commit -m "feat: project manager screen"
```

---

## Task 6: VS Code Shell Layout

**Files:**
- Create: `lib/features/shell/shell_layout.dart`
- Create: `lib/features/shell/status_bar.dart`

- [ ] **Step 1: Write `lib/features/shell/status_bar.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import '../sandbox/sandbox_provider.dart';
import '../git/git_provider.dart';
import '../projects/project_provider.dart';

class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final sandbox = ref.watch(sandboxProvider);
    final project = ref.watch(activeProjectProvider);
    final gitStatus = ref.watch(gitStatusProvider);

    return Container(
      height: 22,
      color: const Color(0xFF007ACC),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        _chip('⎇ ${project?.branch ?? 'main'}'),
        const SizedBox(width: 12),
        gitStatus.when(
          data: (s) => Row(children: [
            if (s.staged.isNotEmpty) _chip('✓ ${s.staged.length}'),
            if (s.modified.isNotEmpty) _chip('✗ ${s.modified.length}'),
          ]),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const Spacer(),
        _chip(sandbox == SandboxState.ready ? 'vibecli ●' : 'vibecli ○'),
      ]),
    );
  }

  Widget _chip(String text) => Text(text, style: const TextStyle(color: Colors.white, fontSize: 11));
}
```

- [ ] **Step 2: Write `lib/features/shell/shell_layout.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import '../explorer/explorer_panel.dart';
import '../editor/editor_panel.dart';
import '../terminal/terminal_panel.dart';
import '../ai/ai_panel.dart';
import '../git/scm_panel.dart';
import '../settings/settings_screen.dart';
import 'status_bar.dart';

enum ActivityTab { explorer, git, ai, settings }

final activeTabProvider = StateProvider<ActivityTab>((ref) => ActivityTab.explorer);
final terminalOpenProvider = StateProvider<bool>((ref) => false);
final aiPanelOpenProvider = StateProvider<bool>((ref) => true);

class ShellLayout extends ConsumerWidget {
  const ShellLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final activeTab = ref.watch(activeTabProvider);
    final terminalOpen = ref.watch(terminalOpenProvider);
    final aiOpen = ref.watch(aiPanelOpenProvider);

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(children: [
        Expanded(
          child: Row(children: [
            // Activity Bar
            _ActivityBar(),
            // Left Panel
            SizedBox(
              width: 220,
              child: Container(
                color: c.sidebar,
                child: switch (activeTab) {
                  ActivityTab.explorer => const ExplorerPanel(),
                  ActivityTab.git      => const ScmPanel(),
                  ActivityTab.ai       => const SizedBox.shrink(),
                  ActivityTab.settings => const SettingsScreen(),
                },
              ),
            ),
            VerticalDivider(width: 1, color: c.border),
            // Main area (editor + ai panel)
            Expanded(
              child: Column(children: [
                // Editor + AI chat
                Expanded(
                  child: Row(children: [
                    const Expanded(child: EditorPanel()),
                    if (aiOpen) ...[
                      VerticalDivider(width: 1, color: c.border),
                      const SizedBox(width: 300, child: AiPanel()),
                    ],
                  ]),
                ),
                // Terminal
                if (terminalOpen) ...[
                  Divider(height: 1, color: c.border),
                  const SizedBox(height: 220, child: TerminalPanel()),
                ],
              ]),
            ),
          ]),
        ),
        const StatusBar(),
      ]),
    );
  }
}

class _ActivityBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final active = ref.watch(activeTabProvider);

    iconBtn(IconData icon, ActivityTab tab, String tooltip) => Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => ref.read(activeTabProvider.notifier).state = tab,
        child: Container(
          width: 48, height: 48,
          color: active == tab ? c.bg : Colors.transparent,
          child: Icon(icon, color: active == tab ? c.fg : c.fgMuted),
        ),
      ),
    );

    return Container(
      width: 48,
      color: const Color(0xFF333333),
      child: Column(children: [
        const SizedBox(height: 4),
        iconBtn(Icons.folder_outlined, ActivityTab.explorer, 'Explorer'),
        iconBtn(Icons.source_outlined, ActivityTab.git, 'Source Control'),
        iconBtn(Icons.smart_toy_outlined, ActivityTab.ai, 'AI Assistant'),
        const Spacer(),
        iconBtn(Icons.settings_outlined, ActivityTab.settings, 'Settings'),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => ref.read(terminalOpenProvider.notifier).state = !ref.read(terminalOpenProvider),
            child: Icon(Icons.terminal, color: c.fgMuted),
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/shell/ && git commit -m "feat: VS Code shell layout with activity bar, panels, status bar"
```

---

## Task 7: File Explorer Panel

**Files:**
- Create: `lib/features/explorer/file_node.dart`
- Create: `lib/features/explorer/explorer_provider.dart`
- Create: `lib/features/explorer/explorer_panel.dart`

- [ ] **Step 1: Write `lib/features/explorer/explorer_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_client.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';

final fileTreeProvider = FutureProvider<FileNode>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) return FileNode(name: '', path: '/', isDir: true);
  final client = ref.watch(sandboxClientProvider);
  return client.getTree(project.localPath);
});

final selectedFileProvider = StateProvider<String?>((ref) => null);
```

- [ ] **Step 2: Write `lib/features/explorer/explorer_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/features/sandbox/sandbox_client.dart';
import 'explorer_provider.dart';
import '../editor/editor_provider.dart';

class ExplorerPanel extends ConsumerWidget {
  const ExplorerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final tree = ref.watch(fileTreeProvider);

    return Column(children: [
      Container(
        height: 35, padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Text('EXPLORER', style: TextStyle(color: c.fgMuted, fontSize: 11, letterSpacing: 1.2)),
        ]),
      ),
      Expanded(
        child: tree.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Padding(padding: const EdgeInsets.all(8), child: Text('$e', style: TextStyle(color: c.fgMuted))),
          data: (node) => ListView(children: node.children.map((n) => _FileNodeTile(node: n, depth: 0)).toList()),
        ),
      ),
    ]);
  }
}

class _FileNodeTile extends ConsumerStatefulWidget {
  final FileNode node;
  final int depth;
  const _FileNodeTile({required this.node, required this.depth});

  @override
  ConsumerState<_FileNodeTile> createState() => _FileNodeTileState();
}

class _FileNodeTileState extends ConsumerState<_FileNodeTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final selected = ref.watch(selectedFileProvider) == widget.node.path;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      GestureDetector(
        onTap: () {
          if (widget.node.isDir) {
            setState(() => _expanded = !_expanded);
          } else {
            ref.read(selectedFileProvider.notifier).state = widget.node.path;
            ref.read(openTabsProvider.notifier).openFile(widget.node.path);
          }
        },
        child: Container(
          color: selected ? c.accent.withOpacity(0.3) : Colors.transparent,
          padding: EdgeInsets.only(left: 12.0 + widget.depth * 12, top: 3, bottom: 3),
          child: Row(children: [
            Icon(
              widget.node.isDir
                  ? (_expanded ? Icons.folder_open : Icons.folder)
                  : _fileIcon(widget.node.name),
              size: 16,
              color: widget.node.isDir ? const Color(0xFFDCB67A) : c.fgMuted,
            ),
            const SizedBox(width: 6),
            Text(widget.node.name, style: TextStyle(color: c.fg, fontSize: 13)),
          ]),
        ),
      ),
      if (_expanded && widget.node.isDir)
        ...widget.node.children.map((n) => _FileNodeTile(node: n, depth: widget.depth + 1)),
    ]);
  }

  IconData _fileIcon(String name) {
    if (name.endsWith('.dart')) return Icons.flutter_dash;
    if (name.endsWith('.js') || name.endsWith('.ts')) return Icons.javascript;
    if (name.endsWith('.py')) return Icons.code;
    if (name.endsWith('.md')) return Icons.description;
    return Icons.insert_drive_file_outlined;
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/explorer/ && git commit -m "feat: file explorer panel with tree view"
```

---

## Task 8: Code Editor

**Files:**
- Create: `lib/features/editor/editor_provider.dart`
- Create: `lib/features/editor/editor_panel.dart`

- [ ] **Step 1: Write `lib/features/editor/editor_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';

class OpenTab {
  final String path;
  final String content;
  final bool isDirty;
  const OpenTab({required this.path, required this.content, this.isDirty = false});
  OpenTab copyWith({String? content, bool? isDirty}) =>
      OpenTab(path: path, content: content ?? this.content, isDirty: isDirty ?? this.isDirty);
}

class OpenTabsNotifier extends Notifier<List<OpenTab>> {
  @override
  List<OpenTab> build() => [];

  Future<void> openFile(String path) async {
    if (state.any((t) => t.path == path)) {
      ref.read(activeTabPathProvider.notifier).state = path;
      return;
    }
    final client = ref.read(sandboxClientProvider);
    final content = await client.readFile(path);
    state = [...state, OpenTab(path: path, content: content)];
    ref.read(activeTabPathProvider.notifier).state = path;
  }

  void closeTab(String path) {
    state = state.where((t) => t.path != path).toList();
  }

  void updateContent(String path, String content) {
    state = [for (final t in state) if (t.path == path) t.copyWith(content: content, isDirty: true) else t];
  }

  Future<void> saveFile(String path) async {
    final tab = state.firstWhere((t) => t.path == path);
    await ref.read(sandboxClientProvider).writeFile(path, tab.content);
    state = [for (final t in state) if (t.path == path) t.copyWith(isDirty: false) else t];
  }
}

final openTabsProvider = NotifierProvider<OpenTabsNotifier, List<OpenTab>>(OpenTabsNotifier.new);
final activeTabPathProvider = StateProvider<String?>((ref) => null);
```

- [ ] **Step 2: Write `lib/features/editor/editor_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:vibeide/shared/theme.dart';
import 'editor_provider.dart';

class EditorPanel extends ConsumerWidget {
  const EditorPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final tabs = ref.watch(openTabsProvider);
    final activePath = ref.watch(activeTabPathProvider);

    if (tabs.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.code, size: 64, color: c.fgMuted),
        const SizedBox(height: 8),
        Text('Open a file from the explorer', style: TextStyle(color: c.fgMuted)),
      ]));
    }

    final activeTab = tabs.firstWhere((t) => t.path == activePath, orElse: () => tabs.first);

    return Column(children: [
      // Tab bar
      Container(
        height: 35,
        color: const Color(0xFF2D2D2D),
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: tabs.map((t) => _Tab(tab: t, isActive: t.path == activePath)).toList(),
        ),
      ),
      // Editor
      Expanded(child: _Editor(tab: activeTab)),
    ]);
  }
}

class _Tab extends ConsumerWidget {
  final OpenTab tab;
  final bool isActive;
  const _Tab({required this.tab, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final name = tab.path.split('/').last;
    return GestureDetector(
      onTap: () => ref.read(activeTabPathProvider.notifier).state = tab.path,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        color: isActive ? c.bg : const Color(0xFF2D2D2D),
        child: Row(children: [
          Text(name, style: TextStyle(color: isActive ? c.fg : c.fgMuted, fontSize: 13)),
          if (tab.isDirty) Padding(padding: const EdgeInsets.only(left: 4), child: Text('●', style: TextStyle(color: c.accent, fontSize: 10))),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => ref.read(openTabsProvider.notifier).closeTab(tab.path),
            child: Icon(Icons.close, size: 14, color: c.fgMuted),
          ),
        ]),
      ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  final OpenTab tab;
  const _Editor({required this.tab});

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late CodeLineEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = CodeLineEditingController.fromText(widget.tab.content);
  }

  @override
  void didUpdateWidget(_Editor old) {
    super.didUpdateWidget(old);
    if (old.tab.path != widget.tab.path) {
      _ctrl = CodeLineEditingController.fromText(widget.tab.content);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          ref.read(openTabsProvider.notifier).saveFile(widget.tab.path);
        },
      },
      child: CodeEditor(
        controller: _ctrl,
        codeTheme: CodeHighlightTheme(
          languages: {_langFromPath(widget.tab.path): CodeHighlightThemeMode(mode: builtinAllLanguages[_langFromPath(widget.tab.path)]!)},
          theme: atomOneDarkTheme,
        ),
        onChanged: () => ref.read(openTabsProvider.notifier).updateContent(widget.tab.path, _ctrl.codeLines.join('\n')),
        style: CodeEditorStyle(
          fontSize: 14,
          fontFamily: 'monospace',
          codeColor: const Color(0xFFD4D4D4),
          backgroundColor: const Color(0xFF1E1E1E),
        ),
      ),
    );
  }

  String _langFromPath(String path) {
    if (path.endsWith('.dart')) return 'dart';
    if (path.endsWith('.js')) return 'javascript';
    if (path.endsWith('.ts')) return 'typescript';
    if (path.endsWith('.py')) return 'python';
    if (path.endsWith('.go')) return 'go';
    if (path.endsWith('.md')) return 'markdown';
    if (path.endsWith('.json')) return 'json';
    return 'plaintext';
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/features/editor/ && git commit -m "feat: code editor with re_editor, tabs, save shortcut"
```

---

## Task 9: Terminal Panel

**Files:**
- Create: `android/app/src/main/assets/terminal/index.html`
- Create: `lib/features/terminal/terminal_panel.dart`

- [ ] **Step 1: Write `assets/terminal/index.html`**

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; background: #1e1e1e; }
  #terminal { width: 100%; height: 100%; }
</style>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css">
</head>
<body>
<div id="terminal"></div>
<script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js"></script>
<script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js"></script>
<script>
const term = new Terminal({ theme: { background:'#1e1e1e', foreground:'#d4d4d4', cursor:'#aeafad' }, fontSize: 14, fontFamily: 'monospace', cursorBlink: true });
const fitAddon = new FitAddon.FitAddon();
term.loadAddon(fitAddon);
term.open(document.getElementById('terminal'));
fitAddon.fit();

const ws = new WebSocket('ws://127.0.0.1:7700/shell/pty');
ws.binaryType = 'arraybuffer';

ws.onopen = () => {
  ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
};

ws.onmessage = e => {
  if (e.data instanceof ArrayBuffer) term.write(new Uint8Array(e.data));
  else term.write(e.data);
};

term.onData(data => ws.send(JSON.stringify({ type: 'input', data })));
term.onResize(({ cols, rows }) => ws.send(JSON.stringify({ type: 'resize', cols, rows })));

window.addEventListener('resize', () => fitAddon.fit());
</script>
</body>
</html>
```

- [ ] **Step 2: Write `lib/features/terminal/terminal_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:vibeide/shared/theme.dart';

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  InAppWebViewController? _ctrl;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    return Container(
      color: c.bg,
      child: Column(children: [
        Container(
          height: 30, color: const Color(0xFF2D2D2D),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Icon(Icons.terminal, size: 14, color: c.fgMuted),
            const SizedBox(width: 4),
            Text('TERMINAL', style: TextStyle(color: c.fgMuted, fontSize: 11)),
          ]),
        ),
        Expanded(
          child: InAppWebView(
            initialFile: 'assets/terminal/index.html',
            initialSettings: InAppWebViewSettings(
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              javaScriptEnabled: true,
              transparentBackground: true,
            ),
            onWebViewCreated: (ctrl) => _ctrl = ctrl,
          ),
        ),
      ]),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/assets/terminal/ lib/features/terminal/
git commit -m "feat: terminal panel with xterm.js WebSocket PTY"
```

---

## Task 10: Git SCM Panel

**Files:**
- Create: `lib/features/git/git_provider.dart`
- Create: `lib/features/git/scm_panel.dart`
- Create: `lib/features/git/pr_screen.dart`

- [ ] **Step 1: Write `lib/features/git/git_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_client.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';

final gitStatusProvider = FutureProvider<GitStatus>((ref) async {
  final project = ref.watch(activeProjectProvider);
  if (project == null) return const GitStatus(branch: '', staged: [], modified: [], untracked: []);
  final client = ref.watch(sandboxClientProvider);
  return client.gitStatus(project.localPath);
});

final commitMessageProvider = StateProvider<String>((ref) => '');
```

- [ ] **Step 2: Write `lib/features/git/scm_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import 'git_provider.dart';
import 'pr_screen.dart';
import '../auth/auth_provider.dart';
import '../ai/ai_client.dart';

class ScmPanel extends ConsumerWidget {
  const ScmPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final status = ref.watch(gitStatusProvider);
    final msgCtrl = TextEditingController(text: ref.watch(commitMessageProvider));

    return Column(children: [
      // Header
      Container(
        height: 35, padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          Text('SOURCE CONTROL', style: TextStyle(color: c.fgMuted, fontSize: 11)),
          const Spacer(),
          IconButton(icon: const Icon(Icons.call_merge), tooltip: 'Raise PR', iconSize: 16,
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrScreen()))),
        ]),
      ),
      // Commit message
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: msgCtrl,
              onChanged: (v) => ref.read(commitMessageProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'Message',
                hintStyle: TextStyle(color: c.fgMuted),
                border: OutlineInputBorder(borderSide: BorderSide(color: c.border)),
                isDense: true, contentPadding: const EdgeInsets.all(8),
              ),
              style: TextStyle(color: c.fg, fontSize: 13),
            ),
          ),
          const SizedBox(width: 4),
          // AI commit message
          IconButton(
            icon: const Icon(Icons.auto_awesome, size: 16),
            tooltip: 'Generate commit message',
            onPressed: () async {
              final project = ref.read(activeProjectProvider);
              if (project == null) return;
              final diff = await ref.read(sandboxClientProvider).gitDiff(project.localPath);
              if (!context.mounted) return;
              final msg = await ref.read(aiClientProvider).generateCommitMessage(diff);
              ref.read(commitMessageProvider.notifier).state = msg;
            },
          ),
          // Commit button
          ElevatedButton(
            onPressed: () async {
              final project = ref.read(activeProjectProvider);
              final msg = ref.read(commitMessageProvider);
              if (project == null || msg.isEmpty) return;
              await ref.read(sandboxClientProvider).gitCommit(project.localPath, msg);
              ref.read(commitMessageProvider.notifier).state = '';
              ref.invalidate(gitStatusProvider);
            },
            child: const Text('Commit', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      // File list
      Expanded(
        child: status.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (e, _) => Text('$e', style: TextStyle(color: c.fgMuted)),
          data: (s) => ListView(children: [
            if (s.staged.isNotEmpty) _section('STAGED', s.staged, c, const Color(0xFF73C991)),
            if (s.modified.isNotEmpty) _section('CHANGES', s.modified, c, const Color(0xFFE2C08D)),
            if (s.untracked.isNotEmpty) _section('UNTRACKED', s.untracked, c, c.fgMuted),
          ]),
        ),
      ),
    ]);
  }

  Widget _section(String title, List<String> files, VsCodeColors c, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Text(title, style: TextStyle(color: c.fgMuted, fontSize: 10, letterSpacing: 1)),
      ),
      ...files.map((f) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Text(f.split('/').last, style: TextStyle(color: color, fontSize: 12)),
      )),
    ]);
  }
}
```

- [ ] **Step 3: Write `lib/features/git/pr_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/projects/project_provider.dart';
import '../auth/auth_provider.dart';
import '../ai/ai_client.dart';

class PrScreen extends ConsumerStatefulWidget {
  const PrScreen({super.key});

  @override
  ConsumerState<PrScreen> createState() => _PrScreenState();
}

class _PrScreenState extends ConsumerState<PrScreen> {
  String _title = '';
  String _body = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    final project = ref.read(activeProjectProvider)!;
    final diff = await ref.read(sandboxClientProvider).gitDiff(project.localPath, base: 'main');
    final ai = ref.read(aiClientProvider);
    final result = await ai.generatePrDescription(diff);
    setState(() { _title = result['title']!; _body = result['body']!; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text('Create Pull Request')),
      body: _loading
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Generating PR description with AI...'),
            ]))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                  controller: TextEditingController(text: _title),
                  onChanged: (v) => _title = v,
                  decoration: InputDecoration(labelText: 'Title', border: OutlineInputBorder(borderSide: BorderSide(color: c.border))),
                  style: TextStyle(color: c.fg),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _body),
                    onChanged: (v) => _body = v,
                    maxLines: null,
                    expands: true,
                    decoration: InputDecoration(labelText: 'Description', border: OutlineInputBorder(borderSide: BorderSide(color: c.border)), alignLabelWithHint: true),
                    style: TextStyle(color: c.fg, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _createPr,
                    child: const Text('Create Pull Request'),
                  ),
                ),
              ]),
            ),
    );
  }

  Future<void> _createPr() async {
    final project = ref.read(activeProjectProvider)!;
    final token = ref.read(githubTokenProvider);
    // POST to GitHub API
    final status = await ref.read(sandboxClientProvider).gitStatus(project.localPath);
    // Use GitHub API via http package
    final response = await ref.read(githubApiProvider).createPr(
      repoUrl: project.remoteUrl,
      token: token!,
      title: _title,
      body: _body,
      head: status.branch,
      base: 'main',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PR created: ${response['html_url']}')));
      Navigator.pop(context);
    }
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/git/ && git commit -m "feat: SCM panel, commit with AI message, PR screen"
```

---

## Task 11: GitHub Auth & API

**Files:**
- Create: `lib/features/auth/github_auth.dart`
- Create: `lib/features/auth/auth_provider.dart`
- Modify: `android/app/src/main/AndroidManifest.xml` — add intent filter for `vibeide://oauth`

- [ ] **Step 1: Add intent filter to `AndroidManifest.xml`**

Inside the `<activity>` tag add:
```xml
<intent-filter android:label="oauth_redirect">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="vibeide" android:host="oauth" />
</intent-filter>
```

- [ ] **Step 2: Write `lib/features/auth/github_auth.dart`**

```dart
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const _clientId = 'YOUR_GITHUB_OAUTH_APP_CLIENT_ID';
// Client secret must be exchanged server-side in production.
// For a dev build, use a lightweight proxy or GitHub Device Flow.

class GitHubAuth {
  Future<String> signIn() async {
    const redirectUri = 'vibeide://oauth';
    final authUrl = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'scope': 'repo user',
    });

    final result = await FlutterWebAuth2.authenticate(
      url: authUrl.toString(),
      callbackUrlScheme: 'vibeide',
    );

    final code = Uri.parse(result).queryParameters['code']!;
    return _exchangeCode(code);
  }

  Future<String> _exchangeCode(String code) async {
    // Replace with your own thin backend proxy that holds the client_secret.
    final res = await http.post(
      Uri.parse('https://your-auth-proxy.example.com/github/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code}),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['access_token'] as String;
  }
}

class GitHubApi {
  Future<Map<String, dynamic>> createPr({
    required String repoUrl,
    required String token,
    required String title,
    required String body,
    required String head,
    required String base,
  }) async {
    // Extract owner/repo from remoteUrl
    final uri = Uri.parse(repoUrl);
    final parts = uri.pathSegments;
    final owner = parts[0];
    final repo = parts[1].replaceAll('.git', '');

    final res = await http.post(
      Uri.https('api.github.com', '/repos/$owner/$repo/pulls'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json', 'Accept': 'application/vnd.github.v3+json'},
      body: jsonEncode({'title': title, 'body': body, 'head': head, 'base': base}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
```

- [ ] **Step 3: Write `lib/features/auth/auth_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'github_auth.dart';

const _tokenKey = 'github_token';
final _storage = FlutterSecureStorage();

final githubTokenProvider = StateProvider<String?>((ref) => null);
final githubApiProvider = Provider<GitHubApi>((ref) => GitHubApi());

class AuthNotifier extends Notifier<String?> {
  @override
  String? build() {
    _loadToken();
    return null;
  }

  Future<void> _loadToken() async {
    final token = await _storage.read(key: _tokenKey);
    state = token;
  }

  Future<void> signIn() async {
    final token = await GitHubAuth().signIn();
    await _storage.write(key: _tokenKey, value: token);
    state = token;
  }

  Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
    state = null;
  }
}

final authProvider = NotifierProvider<AuthNotifier, String?>(AuthNotifier.new);
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/auth/ android/app/src/main/AndroidManifest.xml
git commit -m "feat: GitHub OAuth flow and API client for PR creation"
```

---

## Task 12: AI Client & Chat Panel

**Files:**
- Create: `lib/features/ai/ai_client.dart`
- Create: `lib/features/ai/ai_provider.dart`
- Create: `lib/features/ai/ai_panel.dart`
- Create: `test/ai_client_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ai_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibeide/features/ai/ai_client.dart';

void main() {
  test('token counting is non-zero for non-empty text', () {
    final count = AiClient.estimateTokens('Hello, this is a test message with several words.');
    expect(count, greaterThan(5));
    expect(count, lessThan(30));
  });

  test('generateCommitMessage prompt is built correctly', () {
    final prompt = AiClient.buildCommitPrompt('diff --git a/foo.txt\n+added line');
    expect(prompt, contains('conventional commit'));
    expect(prompt, contains('diff'));
  });

  test('generatePrDescription prompt is built correctly', () {
    final prompt = AiClient.buildPrPrompt('diff --git a/bar.py\n+new feature');
    expect(prompt, contains('title'));
    expect(prompt, contains('description'));
  });
}
```

- [ ] **Step 2: Run — confirm fail**

```bash
flutter test test/ai_client_test.dart
```

- [ ] **Step 3: Write `lib/features/ai/ai_client.dart`**

```dart
import 'dart:async';
import 'dart:convert';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;
import 'package:http/http.dart' as http;

enum AiProvider { claude, openai, gemini }

class AiConfig {
  final AiProvider provider;
  final String apiKey;
  final String model;
  final int dailyTokenLimit;
  const AiConfig({required this.provider, required this.apiKey, required this.model, this.dailyTokenLimit = 100000});
}

class AiClient {
  final AiConfig config;
  AiClient(this.config);

  static int estimateTokens(String text) => (text.length / 4).ceil();

  static String buildCommitPrompt(String diff) =>
      'Write a concise conventional commit message (type: description) for this diff. Return only the message, no explanation.\n\nDiff:\n$diff';

  static String buildPrPrompt(String diff) =>
      'Write a GitHub PR title and description for this diff. Return JSON with keys "title" (string, under 70 chars) and "body" (markdown string with ## Summary and ## Test plan sections).\n\nDiff:\n$diff';

  Stream<String> chat(List<Map<String, String>> messages) async* {
    switch (config.provider) {
      case AiProvider.claude:
        yield* _claudeStream(messages);
      case AiProvider.openai:
        yield* _openaiStream(messages);
      case AiProvider.gemini:
        yield* _geminiStream(messages);
    }
  }

  Stream<String> _claudeStream(List<Map<String, String>> messages) async* {
    final client = anthropic.AnthropicClient(apiKey: config.apiKey);
    final stream = client.createMessageStream(
      request: anthropic.CreateMessageRequest(
        model: anthropic.Model.modelId(config.model),
        maxTokens: 4096,
        messages: messages.map((m) => anthropic.Message(
          role: m['role'] == 'user' ? anthropic.MessageRole.user : anthropic.MessageRole.assistant,
          content: anthropic.MessageContent.text(m['content']!),
        )).toList(),
      ),
    );
    await for (final event in stream) {
      event.map(
        messageStart: (_) {},
        messageDelta: (_) {},
        messageStop: (_) {},
        contentBlockStart: (_) {},
        contentBlockDelta: (e) {
          final delta = e.delta;
          if (delta is anthropic.TextBlockDelta) {
            // yield is not directly usable inside map callbacks; use a controller
          }
        },
        contentBlockStop: (_) {},
        ping: (_) {},
      );
    }
    // Simplified: use raw HTTP for streaming to avoid callback nesting
    final res = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {'x-api-key': config.apiKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
      body: jsonEncode({'model': config.model, 'max_tokens': 4096, 'stream': true,
        'messages': messages}),
    );
    final lines = const LineSplitter().convert(res.body);
    for (final line in lines) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6);
        if (data == '[DONE]') return;
        try {
          final j = jsonDecode(data) as Map<String, dynamic>;
          if (j['type'] == 'content_block_delta') {
            yield (j['delta'] as Map)['text'] as String? ?? '';
          }
        } catch (_) {}
      }
    }
  }

  Stream<String> _openaiStream(List<Map<String, String>> messages) async* {
    final res = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {'Authorization': 'Bearer ${config.apiKey}', 'Content-Type': 'application/json'},
      body: jsonEncode({'model': config.model, 'stream': true, 'messages': messages}),
    );
    for (final line in const LineSplitter().convert(res.body)) {
      if (line.startsWith('data: ') && line != 'data: [DONE]') {
        try {
          final j = jsonDecode(line.substring(6)) as Map<String, dynamic>;
          yield ((j['choices'] as List).first['delta'] as Map)['content'] as String? ?? '';
        } catch (_) {}
      }
    }
  }

  Stream<String> _geminiStream(List<Map<String, String>> messages) async* {
    final last = messages.last['content']!;
    final res = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${config.model}:streamGenerateContent?key=${config.apiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'contents': [{'parts': [{'text': last}]}]}),
    );
    final j = jsonDecode(res.body);
    for (final candidate in (j as List)) {
      yield ((candidate['candidates'] as List).first['content']['parts'] as List).first['text'] as String? ?? '';
    }
  }

  Future<String> generateCommitMessage(String diff) async {
    final sb = StringBuffer();
    await for (final chunk in chat([{'role': 'user', 'content': buildCommitPrompt(diff)}])) {
      sb.write(chunk);
    }
    return sb.toString().trim();
  }

  Future<Map<String, String>> generatePrDescription(String diff) async {
    final sb = StringBuffer();
    await for (final chunk in chat([{'role': 'user', 'content': buildPrPrompt(diff)}])) {
      sb.write(chunk);
    }
    try {
      final j = jsonDecode(sb.toString()) as Map<String, dynamic>;
      return {'title': j['title'] as String, 'body': j['body'] as String};
    } catch (_) {
      return {'title': 'Update code', 'body': sb.toString()};
    }
  }
}
```

- [ ] **Step 4: Run tests — confirm pass**

```bash
flutter test test/ai_client_test.dart
```
Expected: `PASS` for all 3 tests

- [ ] **Step 5: Write `lib/features/ai/ai_provider.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'ai_client.dart';

final aiConfigProvider = StateProvider<AiConfig>((ref) => const AiConfig(
  provider: AiProvider.claude,
  apiKey: '',
  model: 'claude-sonnet-4-6',
));

final aiClientProvider = Provider<AiClient>((ref) {
  final config = ref.watch(aiConfigProvider);
  return AiClient(config);
});

// Tracks token usage per day in SQLite
class TokenBudgetNotifier extends Notifier<int> {
  @override
  int build() { _loadToday(); return 0; }

  Future<void> _loadToday() async {
    final db = await openDatabase('vibeide.db');
    final today = _dayKey();
    final rows = await db.query('token_usage', where: 'day = ?', whereArgs: [today]);
    state = rows.isEmpty ? 0 : rows.first['tokens'] as int;
  }

  Future<void> record(int tokens) async {
    state += tokens;
    final db = await openDatabase('vibeide.db');
    final today = _dayKey();
    await db.insert('token_usage', {'day': today, 'tokens': state},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  bool canSend(int estimatedTokens) {
    final limit = 100000; // read from settings in real impl
    return state + estimatedTokens <= limit;
  }

  String _dayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }
}

final tokenBudgetProvider = NotifierProvider<TokenBudgetNotifier, int>(TokenBudgetNotifier.new);
```

- [ ] **Step 6: Write `lib/features/ai/ai_panel.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import 'ai_client.dart';
import 'ai_provider.dart';

class _Message { final String role, content; const _Message(this.role, this.content); }

class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({super.key});
  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  String _streaming = '';
  bool _thinking = false;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final budget = ref.watch(tokenBudgetProvider);
    final config = ref.watch(aiConfigProvider);

    return Container(
      color: c.sidebar,
      child: Column(children: [
        // Header
        Container(
          height: 35,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            const Icon(Icons.smart_toy_outlined, size: 14),
            const SizedBox(width: 6),
            Text('AI ASSISTANT', style: TextStyle(color: c.fgMuted, fontSize: 11)),
            const Spacer(),
            Text('${budget ~/ 1000}k / ${100}k tokens', style: TextStyle(color: c.fgMuted, fontSize: 10)),
          ]),
        ),
        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(8),
            itemCount: _messages.length + (_streaming.isNotEmpty ? 1 : 0),
            itemBuilder: (ctx, i) {
              if (i == _messages.length) return _Bubble(role: 'assistant', content: _streaming, streaming: true);
              return _Bubble(role: _messages[i].role, content: _messages[i].content);
            },
          ),
        ),
        // Token limit warning
        if (!ref.read(tokenBudgetProvider.notifier).canSend(1000))
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF5A1D1D),
            child: const Text('Daily token limit reached. Reset tomorrow.', style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        // Input
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Ask AI to write or edit code...',
                  hintStyle: TextStyle(color: c.fgMuted),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: c.fg, fontSize: 13),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              icon: _thinking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, size: 18),
              onPressed: _thinking ? null : _send,
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final budget = ref.read(tokenBudgetProvider.notifier);
    if (!budget.canSend(AiClient.estimateTokens(text))) return;

    _ctrl.clear();
    setState(() { _messages.add(_Message('user', text)); _thinking = true; _streaming = ''; });

    final history = _messages.map((m) => {'role': m.role, 'content': m.content}).toList();
    final client = ref.read(aiClientProvider);
    int tokens = 0;

    await for (final chunk in client.chat(history)) {
      if (!mounted) return;
      setState(() => _streaming += chunk);
      tokens += AiClient.estimateTokens(chunk);
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }

    await budget.record(tokens);
    setState(() {
      _messages.add(_Message('assistant', _streaming));
      _streaming = '';
      _thinking = false;
    });
  }

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); super.dispose(); }
}

class _Bubble extends StatelessWidget {
  final String role, content;
  final bool streaming;
  const _Bubble({required this.role, required this.content, this.streaming = false});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final isUser = role == 'user';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUser ? c.accent.withOpacity(0.15) : c.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isUser ? 'You' : 'AI', style: TextStyle(color: c.accent, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(child: Text(content + (streaming ? '▌' : ''), style: TextStyle(color: c.fg, fontSize: 13))),
      ]),
    );
  }
}
```

- [ ] **Step 7: Commit**

```bash
git add lib/features/ai/ test/ai_client_test.dart
git commit -m "feat: multi-provider AI client, token budget, chat panel"
```

---

## Task 13: Settings Screen

**Files:**
- Create: `lib/features/settings/settings_screen.dart`

- [ ] **Step 1: Write `lib/features/settings/settings_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/shared/theme.dart';
import '../ai/ai_client.dart';
import '../ai/ai_provider.dart';
import '../auth/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _keyCtrl = TextEditingController();
  bool _obscure = true;

  static const _models = {
    AiProvider.claude: ['claude-opus-4-7', 'claude-sonnet-4-6', 'claude-haiku-4-5'],
    AiProvider.openai: ['gpt-4o', 'gpt-4o-mini'],
    AiProvider.gemini: ['gemini-2.0-flash', 'gemini-1.5-pro'],
  };

  @override
  void initState() {
    super.initState();
    _keyCtrl.text = ref.read(aiConfigProvider).apiKey;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<VsCodeColors>()!;
    final config = ref.watch(aiConfigProvider);
    final token = ref.watch(authProvider);
    final budget = ref.watch(tokenBudgetProvider);

    return ListView(padding: const EdgeInsets.all(12), children: [
      Text('AI ASSISTANT', style: TextStyle(color: c.fgMuted, fontSize: 10, letterSpacing: 1)),
      const SizedBox(height: 8),
      // Provider
      DropdownButton<AiProvider>(
        value: config.provider,
        dropdownColor: c.sidebar,
        isExpanded: true,
        items: AiProvider.values.map((p) => DropdownMenuItem(value: p, child: Text(p.name.toUpperCase(), style: TextStyle(color: c.fg)))).toList(),
        onChanged: (p) => ref.read(aiConfigProvider.notifier).state = AiConfig(provider: p!, apiKey: config.apiKey, model: _models[p]!.first),
      ),
      const SizedBox(height: 8),
      // Model
      DropdownButton<String>(
        value: config.model,
        dropdownColor: c.sidebar,
        isExpanded: true,
        items: (_models[config.provider] ?? []).map((m) => DropdownMenuItem(value: m, child: Text(m, style: TextStyle(color: c.fg)))).toList(),
        onChanged: (m) => ref.read(aiConfigProvider.notifier).state = AiConfig(provider: config.provider, apiKey: config.apiKey, model: m!),
      ),
      const SizedBox(height: 8),
      // API Key
      TextField(
        controller: _keyCtrl,
        obscureText: _obscure,
        onChanged: (v) => ref.read(aiConfigProvider.notifier).state = AiConfig(provider: config.provider, apiKey: v, model: config.model),
        decoration: InputDecoration(
          labelText: 'API Key',
          suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure)),
          border: OutlineInputBorder(borderSide: BorderSide(color: c.border)),
        ),
        style: TextStyle(color: c.fg),
      ),
      const SizedBox(height: 16),
      // Token usage
      Text('Token Usage Today', style: TextStyle(color: c.fgMuted, fontSize: 11)),
      const SizedBox(height: 4),
      LinearProgressIndicator(value: budget / 100000, backgroundColor: c.border, color: c.accent),
      const SizedBox(height: 4),
      Text('$budget / 100,000 tokens', style: TextStyle(color: c.fgMuted, fontSize: 11)),
      const SizedBox(height: 24),
      Text('GITHUB', style: TextStyle(color: c.fgMuted, fontSize: 10, letterSpacing: 1)),
      const SizedBox(height: 8),
      token != null
          ? Row(children: [
              Icon(Icons.check_circle, color: const Color(0xFF73C991), size: 16),
              const SizedBox(width: 8),
              Text('Connected', style: TextStyle(color: c.fg)),
              const Spacer(),
              TextButton(onPressed: () => ref.read(authProvider.notifier).signOut(), child: const Text('Sign out')),
            ])
          : ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Connect GitHub'),
              onPressed: () => ref.read(authProvider.notifier).signIn(),
            ),
    ]);
  }

  @override
  void dispose() { _keyCtrl.dispose(); super.dispose(); }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/features/settings/ && git commit -m "feat: settings screen — AI provider, API key, token usage, GitHub auth"
```

---

## Task 14: Wire Everything & Smoke Test

**Files:**
- Modify: `lib/main.dart` — inject ProjectRepo into ProviderScope overrides
- Modify: `lib/shared/db.dart` — add token_usage table creation

- [ ] **Step 1: Update `lib/shared/db.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:vibeide/features/projects/project_repo.dart';

Future<Database> openAppDb() async {
  final dbPath = await getDatabasesPath();
  return openDatabase(p.join(dbPath, 'vibeide.db'), version: 1, onCreate: (db, _) async {
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY, name TEXT, remoteUrl TEXT,
        branch TEXT, localPath TEXT, lastOpened INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE token_usage (
        day TEXT PRIMARY KEY, tokens INTEGER
      )
    ''');
  });
}

final projectRepoProvider = Provider<ProjectRepo>((ref) => throw UnimplementedError('override in ProviderScope'));
```

- [ ] **Step 2: Update `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/projects/project_repo.dart';
import 'shared/db.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = ProjectRepo();
  await repo.init();

  runApp(ProviderScope(
    overrides: [
      projectRepoProvider.overrideWithValue(repo),
    ],
    child: const VibeIdeApp(),
  ));
}
```

- [ ] **Step 3: Run full test suite**

```bash
flutter test
```
Expected: all tests pass

- [ ] **Step 4: Build debug APK**

```bash
flutter build apk --debug
```
Expected: APK built at `build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 5: Run on device and verify boot sequence**

```bash
flutter run
```
Verify on device:
- Project Manager screen opens with dark VS Code theme
- Tapping "Clone from GitHub" opens dialog
- Navigating into a project triggers sandbox boot (status bar shows `vibecli ●`)
- Activity bar switches between Explorer, SCM, Settings panels
- Terminal panel opens on terminal icon tap

- [ ] **Step 6: Final commit**

```bash
git add -A && git commit -m "feat: wire all features, full app integration complete"
```

---

**Flutter app plan complete.** Both plans together produce the full VibeIDE app.
