import 'package:flutter/material.dart';

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
/// buttons, menu items and chips. Every other state resolves to null, so it
/// keeps the stock look, and nothing else in [theme] changes. The app uses it
/// only while Flutter's focus highlight mode is traditional (E7 D1); in touch
/// mode it keeps [theme] itself. Built once per theme object.
ThemeData withFocusRings(ThemeData theme) =>
    _withRings[theme] ??= _withRingsOf(theme);

ThemeData _withRingsOf(ThemeData theme) {
  final ring = BorderSide(
    color: focusRingColor(theme.colorScheme),
    width: focusRingWidth,
  );
  BorderSide? side(Set<WidgetState> states) =>
      states.contains(WidgetState.focused) ? ring : null;
  final buttonSide = WidgetStateProperty.resolveWith<BorderSide?>(side);
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
    chipTheme: theme.chipTheme.copyWith(
      side: WidgetStateBorderSide.resolveWith(side),
    ),
  );
}
