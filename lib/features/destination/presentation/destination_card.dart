import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../origin/domain/origin_controller.dart';
import '../../places/presentation/place_search_field.dart';
import '../domain/destination_controller.dart';

/// "Where are you heading to today?" (guide v2.1 §5.5). Shown once an origin
/// is established. Uses the same search component as the manual origin.
class DestinationCard extends ConsumerWidget {
  const DestinationCard({super.key});

  static const String prompt = 'Where are you heading to today?';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasOrigin = ref.watch(
      originControllerProvider.select((s) => s.origin != null),
    );
    if (!hasOrigin) return const SizedBox.shrink();

    final state = ref.watch(destinationControllerProvider);
    final controller = ref.read(destinationControllerProvider.notifier);
    final theme = Theme.of(context);
    final place = state.place;

    final children = <Widget>[];
    if (place != null) {
      children.add(
        Row(
          children: [
            const Icon(Icons.flag_outlined, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'To: ${place.displayName}',
                key: const Key('destination-line'),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
      );
      if (place.address != null) {
        children.add(Text(place.address!, style: theme.textTheme.bodySmall));
      }
    }

    if (place == null || state.editing) {
      children
        ..add(Text(prompt, style: theme.textTheme.titleMedium))
        ..add(const SizedBox(height: 8))
        ..add(
          PlaceSearchField(
            fieldKey: const Key('destination-field'),
            label: 'Destination',
            onSelected: controller.select,
          ),
        );
      if (state.editing) {
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controller.cancelChange,
              child: const Text('Keep this destination'),
            ),
          ),
        );
      }
    } else {
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('change-destination'),
            onPressed: controller.change,
            child: const Text('Change'),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
