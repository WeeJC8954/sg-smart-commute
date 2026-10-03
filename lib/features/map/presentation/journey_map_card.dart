import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/ui/section_heading.dart';
import '../map_providers.dart';
import 'basemap.dart';
import 'journey_map.dart';

/// The optional journey map under the journey card (P2-M1). Nothing until
/// both ends of a journey exist; then a "Show map" button. Only once the user
/// opens it is the map (and so any tile request) built. It stays open across
/// journeys, following the current one, until "Hide map". The journey card
/// never depends on it.
class JourneyMapCard extends ConsumerWidget {
  const JourneyMapCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scene = ref.watch(mapSceneProvider);
    if (scene == null) return const SizedBox.shrink();
    final expanded = ref.watch(mapExpandedProvider);
    final controls = ref.read(mapExpandedProvider.notifier);

    if (!expanded) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          // In line with the cards above (their margin).
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: OutlinedButton.icon(
            key: const Key('show-map'),
            onPressed: controls.show,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Show map'),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Card(
      key: const Key('map-card'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: SectionHeading(
                    'Map',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('hide-map'),
                  onPressed: controls.hide,
                  icon: const Icon(Icons.expand_less),
                  label: const Text('Hide map'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: MapConfig.height,
            child: JourneyMap(scene: scene),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: BasemapAttributionRow(),
          ),
        ],
      ),
    );
  }
}
