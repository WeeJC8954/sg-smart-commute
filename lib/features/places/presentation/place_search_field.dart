import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/ui/status_rows.dart';
import '../domain/place.dart';
import '../domain/place_search_session.dart';
import '../place_providers.dart';

/// One place-search input, shared by origin and destination (guide v2.1
/// §5.3, §5.5, §8.3). Results always need an explicit tap: nothing is
/// selected automatically, even a single match.
class PlaceSearchField extends ConsumerStatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.onSelected,
    this.onEditingStarted,
  });

  static const String hint = 'e.g. 238801, Orchard Road, VivoCity, NUS';

  final Key fieldKey;
  final String label;
  final ValueChanged<Place> onSelected;

  /// Called when the user focuses or types in the field.
  final VoidCallback? onEditingStarted;

  @override
  ConsumerState<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends ConsumerState<PlaceSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final PlaceSearchSession _session;

  @override
  void initState() {
    super.initState();
    _session = PlaceSearchSession(
      ref.read(placeSearchRepositoryProvider),
      debounce: ref.read(placeSearchDebounceProvider),
      minQueryLength: ref.read(placeSearchMinQueryLengthProvider),
    );
    _focus.addListener(() {
      if (_focus.hasFocus) widget.onEditingStarted?.call();
    });
  }

  @override
  void dispose() {
    _session.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(Place place) {
    _controller.clear();
    _session.clear();
    _focus.unfocus();
    widget.onSelected(place);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: widget.fieldKey,
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: PlaceSearchField.hint,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
          ),
          onChanged: (text) {
            widget.onEditingStarted?.call();
            _session.onChanged(text);
          },
          onSubmitted: _session.submit,
        ),
        ValueListenableBuilder<PlaceSearchState>(
          valueListenable: _session.state,
          builder: (context, state, _) => _SearchBody(
            state: state,
            onSelected: _select,
            onRetry: _session.retry,
          ),
        ),
      ],
    );
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.state,
    required this.onSelected,
    required this.onRetry,
  });

  final PlaceSearchState state;
  final ValueChanged<Place> onSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return switch (state) {
      PlaceSearchIdle() => const SizedBox.shrink(),
      PlaceSearchTooShort(:final minLength) => _Note(
        'Type at least $minLength characters, or a 6-digit postal code.',
      ),
      PlaceSearchLoading() => Semantics(
        label: 'Searching places',
        child: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
      ),
      PlaceSearchResults(:final query, :final places) when places.isEmpty =>
        _Note(
          'No places found for "$query". '
          'Try a postal code, street, building or landmark.',
        ),
      PlaceSearchResults(:final places) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              places.length == 1
                  ? '1 match. Tap it to confirm.'
                  : '${places.length} matches. Choose the right one.',
              style: small,
            ),
          ),
          for (final place in places)
            ListTile(
              key: Key('place-${place.id}'),
              leading: Icon(_iconFor(place.type)),
              title: Text(place.displayName),
              subtitle: Text(_detailOf(place)),
              onTap: () => onSelected(place),
            ),
          Text(oneMapAttribution, style: small),
        ],
      ),
      PlaceSearchFailed(:final failure) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ErrorRetryRow(
          message: placeSearchFailureMessage(failure),
          onRetry: onRetry,
        ),
      ),
    };
  }
}

/// User-facing text for a failed place search (guide v2.1 §13).
String placeSearchFailureMessage(AppFailure failure) => switch (failure) {
  NoExactPostalMatch() =>
    '${failure.message} Check the postal code, or search by street or building.',
  ApiUnauthorized() =>
    'Place search is unavailable: OneMap now requires sign-in, '
        'which this app does not use. Please try again later.',
  _ => failure.message,
};

/// Road, building and postcode, so duplicate names can be told apart. An
/// address identical to the name (HDB blocks) is not repeated.
String _detailOf(Place place) {
  final postal = place.postalCode;
  final address = place.distinctAddress;
  if (address == null) return postal ?? 'No address details';
  if (postal != null && !address.contains(postal)) return '$address · $postal';
  return address;
}

IconData _iconFor(PlaceType type) => switch (type) {
  PlaceType.mrtStation => Icons.train_outlined,
  PlaceType.busStop => Icons.directions_bus_outlined,
  PlaceType.building || PlaceType.mall => Icons.business_outlined,
  _ => Icons.place_outlined,
};

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 8), child: Text(text));
}
