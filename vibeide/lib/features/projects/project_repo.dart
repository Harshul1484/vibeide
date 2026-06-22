import 'package:sqflite/sqflite.dart';
import 'project.dart';

class ProjectRepo {
  final String dbPath;
  final bool singleInstance;
  Database? _db;

  ProjectRepo({this.dbPath = 'vibeide.db', this.singleInstance = true});

  Future<void> init() async {
    _db = await openDatabase(
      dbPath,
      version: 1,
      singleInstance: singleInstance,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            remoteUrl TEXT NOT NULL,
            branch TEXT NOT NULL,
            localPath TEXT NOT NULL,
            lastOpened INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE token_usage (
            day TEXT PRIMARY KEY,
            tokens INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> insert(Project p) => _db!.insert(
        'projects',
        p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> delete(String id) =>
      _db!.delete('projects', where: 'id = ?', whereArgs: [id]);

  Future<void> updateName(String id, String name) => _db!.update(
        'projects',
        {'name': name},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> updateBranch(String id, String branch) => _db!.update(
        'projects',
        {'branch': branch},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> touchLastOpened(String id) => _db!.update(
        'projects',
        {'lastOpened': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<List<Project>> listAll() async {
    final rows =
        await _db!.query('projects', orderBy: 'lastOpened DESC');
    return rows.map(Project.fromMap).toList();
  }

  Future<Project?> getById(String id) async {
    final rows = await _db!
        .query('projects', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Project.fromMap(rows.first);
  }

  Future<void> recordTokenUsage(String day, int tokens) async {
    final existing = await _db!
        .query('token_usage', where: 'day = ?', whereArgs: [day]);
    if (existing.isEmpty) {
      await _db!
          .insert('token_usage', {'day': day, 'tokens': tokens});
    } else {
      final current = existing.first['tokens'] as int;
      await _db!.update(
        'token_usage',
        {'tokens': current + tokens},
        where: 'day = ?',
        whereArgs: [day],
      );
    }
  }

  Future<int> getTokenUsage(String day) async {
    final rows = await _db!
        .query('token_usage', where: 'day = ?', whereArgs: [day]);
    return rows.isEmpty ? 0 : rows.first['tokens'] as int;
  }
}
