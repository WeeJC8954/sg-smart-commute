// E7 T1: the keyboard focus ring's contrast on the app's own ten themes
// (WCAG 2.2 SC 1.4.11, 3:1 against adjacent colours). The surfaces are the
// ones a focusable control sits on (plan §1.3, §1.4).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/ui/focus_ring_theme.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

/// The WCAG contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('contrast() matches WCAG: black on white is 21:1', () {
    expect(
      contrast(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      closeTo(21, 1e-9),
    );
  });

  for (final p in AppPalette.values) {
    for (final b in Brightness.values) {
      final s = paletteTheme(p, b).colorScheme;
      final surfaces = {
        'surface (app bar, page, condition tiles)': s.surface,
        'surfaceContainerLow (cards)': s.surfaceContainerLow,
        'surfaceContainer (menu)': s.surfaceContainer,
        'surfaceContainerHigh (dialog)': s.surfaceContainerHigh,
        'surfaceContainerHighest (map without tiles)':
            s.surfaceContainerHighest,
      };
      final layers = {
        'primary': s.primary,
        'onSurface': s.onSurface,
        'onSurfaceVariant': s.onSurfaceVariant,
      };

      test('${p.id} ${b.name}: the ring is at least 3:1 outside and inside '
          'every control', () {
        final ring = focusRingColor(s);
        for (final surface in surfaces.entries) {
          expect(
            contrast(ring, surface.value),
            greaterThanOrEqualTo(3),
            reason: surface.key,
          );
          // Inside: the stock 10 % focus layer stays on the control.
          for (final layer in layers.entries) {
            final inside = Color.alphaBlend(
              layer.value.withValues(alpha: 0.1),
              surface.value,
            );
            expect(
              contrast(ring, inside),
              greaterThanOrEqualTo(3),
              reason: '${surface.key} with a 10 % ${layer.key} layer',
            );
          }
        }
      });

      test('${p.id} ${b.name}: the map ring\'s two colours are at least 3:1 '
          'apart, and the ring is 3:1 on the map card', () {
        expect(
          contrast(focusRingColor(s), focusRingBandColor(s)),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrast(focusRingColor(s), s.surfaceContainerLow),
          greaterThanOrEqualTo(3),
        );
      });
    }
  }
}
