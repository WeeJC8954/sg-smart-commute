import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/errors/app_failure.dart';
import 'place.dart';
import 'place_query.dart';

sealed class PlaceSearchState {
  const PlaceSearchState();
}

/// Nothing typed.
final class PlaceSearchIdle extends PlaceSearchState {
  const PlaceSearchIdle();
}

/// Typed, but shorter than [minPlaceQueryLength] and not a postal code.
final class PlaceSearchTooShort extends PlaceSearchState {
  const PlaceSearchTooShort();
}

final class PlaceSearchLoading extends PlaceSearchState {
  const PlaceSearchLoading(this.query);
  final String query;
}

/// The answer to [query]. Empty [places] means "no results".
final class PlaceSearchResults extends PlaceSearchState {
  const PlaceSearchResults(this.query, this.places);
  final String query;
  final List<Place> places;
}

final class PlaceSearchFailed extends PlaceSearchState {
  const PlaceSearchFailed(this.query, this.failure);
  final String query;
  final AppFailure failure;
}

/// One search field's state (guide v2.1 §8.3): debounced type-ahead, an
/// immediate submit, and a sequence token so an older, slower response
/// never replaces the answer to a newer query.
///
/// It never selects anything itself; the user always picks a result.
class PlaceSearchSession {
  PlaceSearchSession(
    this._repository, {
    this.debounce = const Duration(milliseconds: 350),
  });

  final PlaceSearchRepository _repository;
  final Duration debounce;

  final ValueNotifier<PlaceSearchState> state = ValueNotifier(
    const PlaceSearchIdle(),
  );

  Timer? _timer;
  int _sequence = 0;
  String _lastQuery = '';
  bool _disposed = false;

  /// The text changed: search after [debounce] if it is searchable.
  void onChanged(String raw) => _schedule(raw, SearchMode.typeahead);

  /// Explicit submit (Enter / search key): search now.
  void submit(String raw) => _schedule(raw, SearchMode.submit);

  /// Repeat the last query now (after a failure).
  void retry() => _schedule(_lastQuery, SearchMode.submit);

  /// Back to idle; any in-flight response is ignored.
  void clear() {
    _timer?.cancel();
    _sequence++;
    _lastQuery = '';
    _set(const PlaceSearchIdle());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    state.dispose();
  }

  void _schedule(String raw, SearchMode mode) {
    _timer?.cancel();
    final sequence = ++_sequence;
    final q = PlaceQuery.normalise(raw);
    if (q.text.isEmpty) return _set(const PlaceSearchIdle());
    if (!q.isSearchable) return _set(const PlaceSearchTooShort());

    _lastQuery = q.text;
    _set(PlaceSearchLoading(q.text));
    if (mode == SearchMode.submit) {
      _run(q.text, sequence, mode);
    } else {
      _timer = Timer(debounce, () => _run(q.text, sequence, mode));
    }
  }

  Future<void> _run(String query, int sequence, SearchMode mode) async {
    PlaceSearchState next;
    try {
      next = PlaceSearchResults(
        query,
        await _repository.search(query, mode: mode),
      );
    } on AppFailure catch (failure) {
      next = PlaceSearchFailed(query, failure);
    } catch (e) {
      next = PlaceSearchFailed(query, InvalidApiResponse('$e'));
    }
    // Obsolete: the text changed (or was cleared) while this was in flight.
    if (sequence != _sequence) return;
    _set(next);
  }

  void _set(PlaceSearchState next) {
    if (!_disposed) state.value = next;
  }
}
