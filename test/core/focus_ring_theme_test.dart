// E7 T2 (pure part): withFocusRings adds a ring for the focused state only,
// and touches nothing else in the theme (D1, D3). The palette themes stay
// exactly what E1 made them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/ui/focus_ring_theme.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

const focused = {WidgetState.focused};

/// The states that must keep the stock look (null falls through to it).
const stockStates = <Set<WidgetState>>[
  {},
  {WidgetState.hovered},
  {WidgetState.pressed},
  {WidgetState.hovered, WidgetState.pressed},
  {WidgetState.disabled},
  {WidgetState.selected},
];

void main() {
  for (final p in AppPalette.values) {
    for (final b in Brightness.values) {
      final theme = paletteTheme(p, b);
      final rings = withFocusRings(theme);
      final ring = BorderSide(
        color: theme.colorScheme.primary,
        width: focusRingWidth,
      );
      final styles = {
        'TextButton': rings.textButtonTheme.style,
        'IconButton': rings.iconButtonTheme.style,
        'OutlinedButton': rings.outlinedButtonTheme.style,
        'MenuItemButton': rings.menuButtonTheme.style,
      };

      test('${p.id} ${b.name}: E1 theme unchanged: one seed, no component '
          'theme', () {
        expect(
          theme,
          ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: p.seed, brightness: b),
          ),
        );
      });

      test('${p.id} ${b.name}: buttons and menu items get a 2 px primary '
          'ring when focused, and nothing in any other state', () {
        for (final style in styles.entries) {
          final side = style.value?.side;
          expect(side, isNotNull, reason: style.key);
          expect(side!.resolve(focused), ring, reason: style.key);
          expect(
            side.resolve({WidgetState.focused, WidgetState.hovered}),
            ring,
            reason: '${style.key}: keyboard focus under a resting mouse',
          );
          for (final states in stockStates) {
            expect(
              side.resolve(states),
              isNull,
              reason: '${style.key} $states',
            );
          }
        }
      });

      test('${p.id} ${b.name}: the chip gets the same ring when focused, and '
          'its stock side otherwise', () {
        final side = rings.chipTheme.side;
        expect(WidgetStateProperty.resolveAs<BorderSide?>(side, focused), ring);
        for (final states in stockStates) {
          expect(
            WidgetStateProperty.resolveAs<BorderSide?>(side, states),
            isNull,
            reason: '$states',
          );
        }
      });

      test('${p.id} ${b.name}: nothing else in the theme changes', () {
        expect(
          rings.copyWith(
            textButtonTheme: theme.textButtonTheme,
            iconButtonTheme: theme.iconButtonTheme,
            outlinedButtonTheme: theme.outlinedButtonTheme,
            menuButtonTheme: theme.menuButtonTheme,
            chipTheme: theme.chipTheme,
          ),
          theme,
        );
      });
    }
  }

  test('the ring colours come from the scheme: primary, with a surface band '
      'for the map', () {
    final s = paletteTheme(AppPalette.rose, Brightness.dark).colorScheme;
    expect(focusRingColor(s), s.primary);
    expect(focusRingBandColor(s), s.surface);
    expect(focusRingWidth, 2);
  });

  test('built once per theme object', () {
    final theme = paletteTheme(AppPalette.teal, Brightness.light);
    expect(identical(withFocusRings(theme), withFocusRings(theme)), isTrue);
  });
}
