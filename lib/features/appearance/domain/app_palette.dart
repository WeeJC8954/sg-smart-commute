import 'dart:ui' show Color;

/// The curated colour palettes (E1). Material 3 generates each one's light
/// and dark schemes from its seed alone; the system still picks the
/// brightness. The seeds are the only fixed colours in lib/
/// (test/app/app_theme_test.dart).
enum AppPalette {
  teal('teal', 'Teal', Color(0xFF009688)),
  blue('blue', 'Blue', Color(0xFF0288D1)),
  rose('rose', 'Rose', Color(0xFFE91E63)),
  purple('purple', 'Purple', Color(0xFF9C27B0)),
  orange('orange', 'Orange', Color(0xFFFF9800));

  const AppPalette(this.id, this.label, this.seed);

  /// What is stored on the device. Never rename or reuse one: a stored id
  /// that matches no palette becomes [fallback].
  final String id;

  /// The name shown in the selector; free to change.
  final String label;

  /// The Material 3 seed (teal is `Colors.teal`'s value, so the default
  /// theme is unchanged).
  final Color seed;

  /// The default, and what any unknown or unreadable stored value becomes.
  static const AppPalette fallback = teal;

  static AppPalette fromId(String? id) {
    for (final p in values) {
      if (p.id == id) return p;
    }
    return fallback;
  }
}
