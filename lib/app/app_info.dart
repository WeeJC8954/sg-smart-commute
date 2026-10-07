import 'package:flutter/services.dart' show appBuildName, appBuildNumber;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's version and build (E4), as the flutter tool compiled them in from
/// pubspec `version: <version>+<build>`.
class AppInfo {
  const AppInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  /// "Version <version> (<build>)", or "Version <version>" when the build has
  /// no number.
  String get label => buildNumber.isEmpty
      ? 'Version $version'
      : 'Version $version ($buildNumber)';
}

/// [name] and [number] as compiled in; null when the build carried no version,
/// so About says "Version unavailable".
AppInfo? appInfoFrom(String? name, String? number) =>
    name == null || name.isEmpty
    ? null
    : AppInfo(version: name, buildNumber: number ?? '');

/// The version the flutter tool compiled in (Flutter 3.47+ `appBuildName` /
/// `appBuildNumber`): no plugin, no I/O, no request. Tests override it.
final appInfoProvider = Provider<AppInfo?>(
  (ref) => appInfoFrom(appBuildName, appBuildNumber),
);
