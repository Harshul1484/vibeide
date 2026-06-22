import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibeide/features/sandbox/sandbox_provider.dart';
import 'package:vibeide/features/extensions/extension_catalog.dart';
import 'package:vibeide/features/extensions/extensions_provider.dart';

/// True once the user dismisses the Welcome tab via its × button. When no
/// file is open and this is true, the editor shows a plain empty area.
final welcomeClosedProvider = StateProvider<bool>((ref) => false);

/// When true, saving a file will also run the formatter (if one is installed).
final formatOnSaveProvider = StateProvider<bool>((ref) => true);

class OpenTab {
  final String path;
  final String content;
  final bool isDirty;

  const OpenTab({
    required this.path,
    required this.content,
    this.isDirty = false,
  });

  OpenTab copyWith({String? content, bool? isDirty}) => OpenTab(
        path: path,
        content: content ?? this.content,
        isDirty: isDirty ?? this.isDirty,
      );
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
    if (ref.read(activeTabPathProvider) == path) {
      ref.read(activeTabPathProvider.notifier).state =
          state.isEmpty ? null : state.last.path;
    }
  }

  void updateContent(String path, String content) {
    state = [
      for (final t in state)
        if (t.path == path) t.copyWith(content: content, isDirty: true) else t
    ];
  }

  Future<void> saveFile(String path) async {
    final tab = state.firstWhere((t) => t.path == path);
    await ref.read(sandboxClientProvider).writeFile(path, tab.content);
    state = [
      for (final t in state)
        if (t.path == path) t.copyWith(isDirty: false) else t
    ];
  }

  /// Saves the file, then optionally formats it if format-on-save is enabled
  /// and a formatter is installed for the file type.
  Future<void> saveAndMaybeFormat(String path) async {
    await saveFile(path);
    final formatOnSave = ref.read(formatOnSaveProvider);
    if (!formatOnSave) return;
    final installedIds =
        ref.read(installedToolsProvider).valueOrNull ?? const {};
    final formatter = formatterFor(path, installedIds);
    if (formatter == null) return;
    final cmd = formatter.formatCmd!.replaceAll('{file}', path);
    final (exitCode, _) = await ref
        .read(sandboxClientProvider)
        .execToCompletion('/bin/sh', ['-lc', cmd]);
    if (exitCode == 0) {
      await reloadFile(path);
    }
  }

  /// Re-reads the file from the sandbox and replaces the tab's content,
  /// marking it clean. Used after format-on-save so the editor shows the
  /// reformatted text without marking the file dirty.
  Future<void> reloadFile(String path) async {
    final content = await ref.read(sandboxClientProvider).readFile(path);
    state = [
      for (final t in state)
        if (t.path == path)
          OpenTab(path: t.path, content: content, isDirty: false)
        else
          t
    ];
  }
}

final openTabsProvider =
    NotifierProvider<OpenTabsNotifier, List<OpenTab>>(OpenTabsNotifier.new);

final activeTabPathProvider = StateProvider<String?>((ref) => null);
