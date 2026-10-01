/// Query normalisation for place search (guide v2.1 §8.3, M0 findings in
/// docs/api-feasibility.md §4.3).
library;

final RegExp _postalCode = RegExp(r'^\d{6}$');
final RegExp _whitespace = RegExp(r'\s+');

/// A leading "Blk" / "Block" (optionally "Blk."), followed by a block number
/// and at least one more word: `Blk 123 Ang Mo Kio Ave 6`.
final RegExp _blockPrefix = RegExp(
  r'^(?:blk|block)\.?\s*(?=\d+[a-z]?\s+\S)',
  caseSensitive: false,
);

/// Minimum length for a non-postal-code query (§8.3).
const int minPlaceQueryLength = 3;

/// True for exactly six digits; a leading zero is allowed (`098585`).
bool isPostalCode(String value) => _postalCode.hasMatch(value);

class PlaceQuery {
  const PlaceQuery._(this.text, {required this.isPostalCode});

  /// Trims and collapses whitespace. Strips a leading `Blk` / `Block` before
  /// a block number and street, because OneMap returns nothing for
  /// `Blk 123 Ang Mo Kio Ave 6` but finds `123 Ang Mo Kio Ave 6`. A bare
  /// `Block 71` (a place name) is kept as typed.
  factory PlaceQuery.normalise(String raw) {
    var text = raw.trim().replaceAll(_whitespace, ' ');
    text = text.replaceFirst(_blockPrefix, '');
    return PlaceQuery._(text, isPostalCode: _postalCode.hasMatch(text));
  }

  /// The normalised query string, which is also the cache key.
  final String text;

  /// The query is exactly a 6-digit postal code: results must match it exactly.
  final bool isPostalCode;

  /// Long enough to search: 3+ characters, or a valid postal code.
  bool get isSearchable => isPostalCode || text.length >= minPlaceQueryLength;

  @override
  String toString() => 'PlaceQuery($text)';
}
