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
      } else {
        req.response
          ..statusCode = 404
          ..close();
      }
    });
    client = SandboxClient(port: server.port);
  });

  tearDown(() => server.close(force: true));

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
    expect(status.staged, isEmpty);
  });
}
