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
    final repo = ProjectRepo(dbPath: ':memory:', singleInstance: false);
    await repo.init();

    final p = Project(
      id: 'abc',
      name: 'my-app',
      remoteUrl: 'https://github.com/u/r',
      branch: 'main',
      localPath: '/root/projects/abc',
      lastOpened: DateTime(2024, 1, 1),
    );
    await repo.insert(p);

    final list = await repo.listAll();
    expect(list.length, 1);
    expect(list.first.name, 'my-app');
    expect(list.first.branch, 'main');
  });

  test('update last opened', () async {
    final repo = ProjectRepo(dbPath: ':memory:', singleInstance: false);
    await repo.init();
    final p = Project(
      id: 'x',
      name: 'p',
      remoteUrl: '',
      branch: 'main',
      localPath: '/root/x',
      lastOpened: DateTime(2020),
    );
    await repo.insert(p);
    await repo.touchLastOpened('x');
    final updated = await repo.getById('x');
    expect(updated!.lastOpened.year, greaterThan(2020));
  });

  test('delete project', () async {
    final repo = ProjectRepo(dbPath: ':memory:', singleInstance: false);
    await repo.init();
    final p = Project(
      id: 'del',
      name: 'to-delete',
      remoteUrl: '',
      branch: 'main',
      localPath: '/root/del',
      lastOpened: DateTime.now(),
    );
    await repo.insert(p);
    await repo.delete('del');
    final list = await repo.listAll();
    expect(list, isEmpty);
  });
}
