import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'features/projects/project_repo.dart';
import 'shared/db.dart';
import 'app.dart';

Future<ProjectRepo> _initDb() async {
  final dbPath = await getDatabasesPath();
  final repo = ProjectRepo(
    dbPath: path.join(dbPath, 'vibeide.db'),
  );
  await repo.init();
  return repo;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await _initDb();

  runApp(
    ProviderScope(
      overrides: [
        projectRepoProvider.overrideWithValue(repo),
      ],
      child: const VibeIdeApp(),
    ),
  );
}
