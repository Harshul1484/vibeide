import 'package:flutter/widgets.dart';

/// VS Code Codicons — the official icon font used throughout VS Code.
/// Font: assets/fonts/codicon.ttf (from @vscode/codicons)
///
/// Usage: `Icon(Codicons.folder, size: 20, color: ...)`
class Codicons {
  Codicons._();

  static const _family = 'codicon';

  static const IconData folder = IconData(0xea83, fontFamily: _family);
  static const IconData folderOpened = IconData(0xeaf7, fontFamily: _family);
  static const IconData files = IconData(0xeaf0, fontFamily: _family);
  static const IconData search = IconData(0xea6d, fontFamily: _family);
  static const IconData sourceControl = IconData(0xea68, fontFamily: _family);
  static const IconData gitCommit = IconData(0xeafc, fontFamily: _family);
  static const IconData gitPullRequest = IconData(0xea64, fontFamily: _family);
  static const IconData gitBranch = IconData(0xec6f, fontFamily: _family);
  static const IconData settingsGear = IconData(0xeb51, fontFamily: _family);
  static const IconData terminal = IconData(0xea85, fontFamily: _family);
  static const IconData file = IconData(0xea7b, fontFamily: _family);
  static const IconData fileCode = IconData(0xeae9, fontFamily: _family);
  static const IconData close = IconData(0xea76, fontFamily: _family);
  static const IconData add = IconData(0xea60, fontFamily: _family);
  static const IconData chevronRight = IconData(0xeab6, fontFamily: _family);
  static const IconData chevronDown = IconData(0xeab4, fontFamily: _family);
  static const IconData account = IconData(0xeb99, fontFamily: _family);
  static const IconData cloudDownload = IconData(0xeac2, fontFamily: _family);
  static const IconData check = IconData(0xeab2, fontFamily: _family);
  static const IconData circleFilled = IconData(0xea71, fontFamily: _family);
  static const IconData circleOutline = IconData(0xeabc, fontFamily: _family);
  static const IconData sync = IconData(0xea77, fontFamily: _family);
  static const IconData sparkle = IconData(0xec10, fontFamily: _family);
  static const IconData send = IconData(0xec0f, fontFamily: _family);
  static const IconData trash = IconData(0xea81, fontFamily: _family);
  static const IconData json = IconData(0xeb0f, fontFamily: _family);
  static const IconData markdown = IconData(0xeb1d, fontFamily: _family);
  static const IconData symbolFile = IconData(0xeb60, fontFamily: _family);
  static const IconData library = IconData(0xeb9c, fontFamily: _family);
  static const IconData warning = IconData(0xea6c, fontFamily: _family);
  static const IconData error = IconData(0xea87, fontFamily: _family);
  static const IconData refresh = IconData(0xeb37, fontFamily: _family);
  static const IconData link = IconData(0xeb15, fontFamily: _family);
  static const IconData signOut = IconData(0xea6e, fontFamily: _family);
  static const IconData robot = IconData(0xec20, fontFamily: _family);
  static const IconData play = IconData(0xeb2c, fontFamily: _family);

  /// Maps a filename to the appropriate codicon, like VS Code's file icons.
  static IconData forFile(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart') ||
        lower.endsWith('.js') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.py') ||
        lower.endsWith('.go') ||
        lower.endsWith('.kt') ||
        lower.endsWith('.java') ||
        lower.endsWith('.c') ||
        lower.endsWith('.cpp') ||
        lower.endsWith('.rs') ||
        lower.endsWith('.rb') ||
        lower.endsWith('.sh')) {
      return fileCode;
    }
    if (lower.endsWith('.json')) return json;
    if (lower.endsWith('.md')) return markdown;
    return file;
  }
}
