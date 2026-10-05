import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appearance_providers.dart';
import '../domain/app_palette.dart';
import 'palette_theme.dart';

/// The app-bar control for the colour palette (E1): a menu of the curated
/// palettes, each named, with a radio mark and a swatch of its primary
/// colour in the current brightness. Choosing one applies it at once. It
/// holds no palette state of its own: it reads and sets paletteProvider.
class PaletteMenuButton extends ConsumerWidget {
  const PaletteMenuButton({super.key});

  static String tooltipFor(AppPalette palette) =>
      'Colour theme: ${palette.label}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(paletteProvider);
    final brightness = Theme.of(context).brightness;
    return MenuAnchor(
      menuChildren: [
        for (final p in AppPalette.values)
          RadioMenuButton<AppPalette>(
            key: Key('palette-option-${p.id}'),
            value: p,
            groupValue: current,
            onChanged: (p) {
              if (p != null) ref.read(paletteProvider.notifier).select(p);
            },
            trailingIcon: PaletteSwatch(
              paletteTheme(p, brightness).colorScheme.primary,
            ),
            child: Text(p.label),
          ),
      ],
      // One node: the button, its name (tooltip) and whether the menu is
      // open (aria-expanded on Web). Added because the open/closed test
      // failed with plain Material.
      builder: (context, controller, _) => MergeSemantics(
        child: Semantics(
          expanded: controller.isOpen,
          child: IconButton(
            key: const Key('palette-button'),
            tooltip: tooltipFor(current),
            icon: const Icon(Icons.palette_outlined),
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
          ),
        ),
      ),
    );
  }
}

/// A round preview of a palette's primary colour. Decorative: each option
/// is named, so colour is never the only cue.
class PaletteSwatch extends StatelessWidget {
  const PaletteSwatch(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 18,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
    ),
  );
}
