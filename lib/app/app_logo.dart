import 'package:flutter/material.dart';

import 'app.dart';

/// The app-bar title: the icon, then the app name. On a narrow screen the
/// name is shortened with an ellipsis; the icon keeps its size.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppLogo(key: Key('app-logo')),
      SizedBox(width: 10),
      Flexible(
        child: Text(SmartCommuteApp.title, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// The app icon (bus, Singapore skyline and a destination pin).
///
/// [asset] is cropped to its rounded tile with transparent corners, 192 px
/// square, so it stays sharp up to 6× the default size.
///
/// Decorative: it always sits next to the app title, so screen readers skip it.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  static const String asset = 'assets/app_icon.png';

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    ),
  );
}
