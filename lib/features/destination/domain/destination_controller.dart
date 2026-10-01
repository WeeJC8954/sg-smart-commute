import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../places/domain/place.dart';

class DestinationState {
  const DestinationState({this.place, this.editing = false});

  /// The selected destination, if any. Kept while the user is changing it.
  final Place? place;

  /// The user reopened the search to change [place].
  final bool editing;
}

/// The destination (guide v2.1 §5.5). Separate from the origin controller,
/// so choosing a destination can never change the origin.
class DestinationController extends Notifier<DestinationState> {
  @override
  DestinationState build() => const DestinationState();

  /// The user explicitly selected a search result.
  void select(Place place) => state = DestinationState(place: place);

  /// Reopen the search; the current destination stays until a new one is
  /// chosen.
  void change() => state = DestinationState(place: state.place, editing: true);

  /// Close the search without changing the destination.
  void cancelChange() => state = DestinationState(place: state.place);
}

final destinationControllerProvider =
    NotifierProvider<DestinationController, DestinationState>(
      DestinationController.new,
    );
