import 'package:flutter/material.dart';

import '../domain/app_palette.dart';

final _themes = <(AppPalette, Brightness), ThemeData>{};

/// The app theme for [palette] in [brightness]: the Material 3 scheme from
/// the palette's one seed (no role tuned by hand), built once each. Widgets
/// take colours only from the scheme, never fixed values.
ThemeData paletteTheme(AppPalette palette, Brightness brightness) =>
    _themes[(palette, brightness)] ??= ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: palette.seed,
        brightness: brightness,
      ),
    );
