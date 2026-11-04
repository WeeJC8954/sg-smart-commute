import 'package:flutter/material.dart';

import 'focus_highlight_scope.dart';

/// The app's focus ring theme (E7), installed once in `MaterialApp.builder`
/// above the navigator, so it covers every page, dialog and menu. In
/// traditional highlight mode it adds [withFocusRings] to the theme above;
/// in touch mode it passes that theme on unchanged.
class FocusRingTheme extends StatelessWidget {
  const FocusRingTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FocusHighlightScope(child: Builder(builder: _themed));

  Widget _themed(BuildContext context) {
    final theme = Theme.of(context);
    // Always a Theme, so the subtree keeps its state across a mode change.
    return Theme(
      data: FocusHighlightScope.showsFocusOf(context)
          ? withFocusRings(theme)
          : theme,
      child: child,
    );
  }
}

/// The keyboard focus ring's width (E7), the same as [FocusRing]'s.
const double focusRingWidth = 2;

/// The ring's colour: the scheme's primary. It is at least 3:1 against every
/// surface a control sits on, in all ten themes (E7 plan §1.3; checked by
/// `test/core/focus_ring_contrast_test.dart`).
Color focusRingColor(ColorScheme scheme) => scheme.primary;

/// The band inside the map's two-colour ring (E7 D2), which keeps the ring
/// visible over any map tile.
Color focusRingBandColor(ColorScheme scheme) => scheme.surface;

final _withRings = Expando<ThemeData>('withFocusRings');

/// [theme] with a [focusRingWidth] ring in [focusRingColor] on focused
/// buttons and menu items. Every other state resolves to null, so it keeps
/// the stock look, and nothing else in [theme] changes. The app uses it only
/// while Flutter's focus highlight mode is traditional (E7 D1); in touch mode
/// it keeps [theme] itself. Built once per theme object.
///
/// Chips are not ringed here: Flutter 3.47.2 `ChipThemeData.lerp` throws on a
/// state side that is null at rest, and each button lerps its theme on every
/// theme change. A chip gets `FocusRingWithin` instead.
ThemeData withFocusRings(ThemeData theme) =>
    _withRings[theme] ??= _withRingsOf(theme);

ThemeData _withRingsOf(ThemeData theme) {
  final ring = BorderSide(
    color: focusRingColor(theme.colorScheme),
    width: focusRingWidth,
  );
  final buttonSide = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) => states.contains(WidgetState.focused) ? ring : null,
  );
  ButtonStyle ringed(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(side: buttonSide);

  return theme.copyWith(
    textButtonTheme: TextButtonThemeData(
      style: ringed(theme.textButtonTheme.style),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ringed(theme.iconButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ringed(theme.outlinedButtonTheme.style),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ringed(theme.menuButtonTheme.style),
    ),
  );
}
