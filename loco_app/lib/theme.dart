import 'package:flutter/material.dart';

/// LOCO brand colours and theme helpers (same palette as the website).
class LC {
  static const purple = Color(0xFF7045D8);
  static const blue = Color(0xFF38BDF8);
  static const pink = Color(0xFFEC70BB);
  static const midBlue = Color(0xFF4F7DE8);

  static const darkBg = Color(0xFF0B1020);
  static const darkCard = Color(0xFF151E32);
  static const darkCard2 = Color(0xFF1C2842);
  static const darkCell = Color(0xFF202C46);
  static const lightBg = Color(0xFFEDF1FA);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightCard2 = Color(0xFFF2F5FC);
  static const lightCell = Color(0xFFEEF2FB);

  static const gradient = LinearGradient(
    colors: [purple, midBlue, blue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color bg(BuildContext c) => isDark(c) ? darkBg : lightBg;
  static Color card(BuildContext c) => isDark(c) ? darkCard : lightCard;
  static Color card2(BuildContext c) => isDark(c) ? darkCard2 : lightCard2;
  static Color cell(BuildContext c) => isDark(c) ? darkCell : lightCell;
  static Color border(BuildContext c) =>
      isDark(c) ? const Color(0x14FFFFFF) : const Color(0x1A141E3C);
  static Color accent(BuildContext c) => isDark(c) ? blue : const Color(0xFF0A7FC0);
  static Color soft(BuildContext c) =>
      isDark(c) ? const Color(0x9EE6ECF8) : const Color(0x9E1B2440);
  static Color text(BuildContext c) =>
      isDark(c) ? const Color(0xFFE6ECF8) : const Color(0xFF1B2440);

  static ThemeData theme(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: purple, brightness: b).copyWith(
      primary: purple,
      secondary: blue,
      tertiary: pink,
      surface: dark ? darkCard : lightCard,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? darkBg : lightBg,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? darkCard2 : const Color(0xFF1B2440),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
