import 'package:shared_preferences/shared_preferences.dart';

import '../domain/palette_store.dart';

/// [PaletteStore] on shared_preferences: app storage on Android, the
/// browser's localStorage on Web. Nothing leaves the device.
class SharedPreferencesPaletteStore implements PaletteStore {
  static const String key = 'colour_palette';

  // Created on first use, inside the async calls: without a platform
  // implementation the constructor throws, which then surfaces as a failed
  // Future that every caller already handles.
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read() async => _prefs.getString(key);

  @override
  Future<void> write(String id) async => _prefs.setString(key, id);
}
