import 'package:flutter/material.dart';

const _bg = Color(0xFF1E1E1E);
const _sidebar = Color(0xFF252526);
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
    onPrimary: Colors.white,
    onSurface: _fg,
    outline: _border,
  ),
  dividerColor: _border,
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _accent,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFF2D2D2D),
      disabledForegroundColor: _fgMuted,
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: _accent),
  ),
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
  extensions: const [
    VsCodeColors(
      bg: _bg,
      sidebar: _sidebar,
      border: _border,
      accent: _accent,
      fg: _fg,
      fgMuted: _fgMuted,
    ),
  ],
);

class VsCodeColors extends ThemeExtension<VsCodeColors> {
  const VsCodeColors({
    required this.bg,
    required this.sidebar,
    required this.border,
    required this.accent,
    required this.fg,
    required this.fgMuted,
  });

  final Color bg, sidebar, border, accent, fg, fgMuted;

  @override
  VsCodeColors copyWith({
    Color? bg,
    Color? sidebar,
    Color? border,
    Color? accent,
    Color? fg,
    Color? fgMuted,
  }) =>
      VsCodeColors(
        bg: bg ?? this.bg,
        sidebar: sidebar ?? this.sidebar,
        border: border ?? this.border,
        accent: accent ?? this.accent,
        fg: fg ?? this.fg,
        fgMuted: fgMuted ?? this.fgMuted,
      );

  @override
  VsCodeColors lerp(VsCodeColors? other, double t) => this;
}
