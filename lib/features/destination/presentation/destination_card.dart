import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/section_heading.dart';
import '../../origin/domain/origin_controller.dart';
import '../../places/presentation/place_search_field.dart';
import '../domain/destination_controller.dart';

/// The destination section of the route card (lib/app/route_card.dart),
/// shown once an origin exists: "Where are you heading to today?" (guide v2.1
/// §5.5). Uses the same search component as the manual origin.
///
/// Focus follows the flow as in the origin card: "Change" opens a focused
/// field, and picking a place (or "Keep this destination") focuses "Change".
class DestinationCard extends ConsumerStatefulWidget {
  const DestinationCard({super.key});

  static const String prompt = 'Where are you heading to today?';

  @override
  ConsumerState<DestinationCard> createState() => _DestinationCardState();
}

class _DestinationCardState extends ConsumerState<DestinationCard> {
  final _changeButton = FocusNode(debugLabel: 'change-destination');

  @override
  void dispose() {
    _changeButton.dispose();
    super.dispose();
  }

  /// Focuses "Change" once the rebuild that shows it has run.
  void _focusChangeAfterRebuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changeButton.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
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
      final address = place.distinctAddress;
      if (address != null) {
        children.add(Text(address, style: theme.textTheme.bodySmall));
      }
    }

    if (place == null || state.editing) {
      children
        ..add(
          SectionHeading(
            DestinationCard.prompt,
            style: theme.textTheme.titleMedium,
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(
          PlaceSearchField(
            fieldKey: const Key('destination-field'),
            label: 'Destination',
            // Only after "Change"; the first prompt doesn't pop the keyboard.
            autofocus: state.editing,
            onSelected: (place) {
              controller.select(place);
              _focusChangeAfterRebuild();
            },
          ),
        );
      if (state.editing) {
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                controller.cancelChange();
                _focusChangeAfterRebuild();
              },
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
            focusNode: _changeButton,
            onPressed: controller.change,
            // The origin has a "Change" too.
            child: const Text('Change', semanticsLabel: 'Change destination'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const Divider(height: 24), ...children],
    );
  }
}
