import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';

void main() {
  test('the stored ids are stable and in menu order', () {
    // Stored on devices: never rename or reuse one.
    expect(AppPalette.values.map((p) => p.id), [
      'teal',
      'blue',
      'rose',
      'purple',
      'orange',
    ]);
  });

  test('the stored ids are unique', () {
    expect(
      AppPalette.values.map((p) => p.id).toSet(),
      hasLength(AppPalette.values.length),
    );
  });

  test('each palette has its display name', () {
    expect(AppPalette.values.map((p) => p.label), [
      'Teal',
      'Blue',
      'Rose',
      'Purple',
      'Orange',
    ]);
  });

  test('the seeds are exactly the five approved values', () {
    expect(AppPalette.values.map((p) => p.seed.toARGB32()), [
      0xFF009688,
      0xFF0288D1,
      0xFFE91E63,
      0xFF9C27B0,
      0xFFFF9800,
    ]);
  });

  test('fromId: each stored id; teal for nothing, an unknown id or a name', () {
    for (final p in AppPalette.values) {
      expect(AppPalette.fromId(p.id), p);
    }
    expect(AppPalette.fallback, AppPalette.teal);
    expect(AppPalette.fromId(null), AppPalette.teal);
    expect(
      AppPalette.fromId('indigo'),
      AppPalette.teal,
      reason: 'never shipped',
    );
    expect(AppPalette.fromId('magenta'), AppPalette.teal);
    expect(
      AppPalette.fromId('Purple'),
      AppPalette.teal,
      reason: 'a name is not an id',
    );
  });
}
