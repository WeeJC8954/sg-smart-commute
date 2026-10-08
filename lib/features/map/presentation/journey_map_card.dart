import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/section_heading.dart';
import '../map_providers.dart';
import 'basemap.dart';
import 'journey_map.dart';

/// The optional journey map under the journey card (P2-M1). Nothing until
/// both ends of a journey exist; then a "Show map" button. Only once the user
/// opens it is the map (and so any tile request) built. It stays open across
/// journeys, following the current one, until "Hide map". The journey card
/// never depends on it.
///
/// Each of "Show map" and "Hide map" replaces itself with the other, so
/// focus moves to the other one (#56).
class JourneyMapCard extends ConsumerStatefulWidget {
  const JourneyMapCard({super.key});

  @override
  ConsumerState<JourneyMapCard> createState() => _JourneyMapCardState();
}

class _JourneyMapCardState extends ConsumerState<JourneyMapCard> {
  final _show = FocusNode(debugLabel: 'show-map');
  final _hide = FocusNode(debugLabel: 'hide-map');

  @override
  void dispose() {
    _show.dispose();
    _hide.dispose();
    super.dispose();
  }

  /// Runs [toggle], then focuses [next] once the rebuild has shown it.
  void _toggle(VoidCallback toggle, FocusNode next) {
    toggle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) next.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
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
            focusNode: _show,
            onPressed: () => _toggle(controls.show, _hide),
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
                  focusNode: _hide,
                  onPressed: () => _toggle(controls.hide, _show),
                  icon: const Icon(Icons.expand_less),
                  label: const Text('Hide map'),
                ),
              ],
            ),
          ),
          JourneyMap(scene: scene),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: BasemapAttributionRow(),
          ),
        ],
      ),
    );
  }
}
