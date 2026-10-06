/// Where the chosen palette's id is kept between launches (E1): on this
/// device only; the value is not sensitive.
abstract interface class PaletteStore {
  /// The stored id, or null if none was stored.
  Future<String?> read();

  Future<void> write(String id);
}
