import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_info.dart';
import 'app_logo.dart';

/// The app-bar About action (E4). An info icon named for the app; the logo
/// and title beside it stay decorative.
class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  static const String tooltip = 'About ${SmartCommuteApp.title}';

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('about-button'),
    tooltip: tooltip,
    icon: const Icon(Icons.info_outline),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => const AboutAppDialog(),
    ),
  );
}

/// Name, description, author and the compiled-in version, then "View
/// licenses" and "Close". A small AlertDialog rather than showAboutDialog,
/// whose fixed header reads the version before the description and squeezes
/// the name beside the icon (Phase A plan §2.4).
class AboutAppDialog extends ConsumerWidget {
  const AboutAppDialog({super.key});

  static const String description =
      'Singapore Smart Commute is a front-end-only commute helper for '
      'Singapore. It combines current conditions, bus journey suggestions, '
      'live bus arrivals, MRT alternatives, and an optional journey map.';
  static const String author = 'Author: Jaycee Wee';
  static const String versionUnavailable = 'Version unavailable';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);
    // Names the alert-dialog node itself. AlertDialog puts its own label on an
    // inner route node, so on the Web the dialog had no accessible name.
    return Semantics(
      namesRoute: true,
      label: SmartCommuteApp.title,
      child: AlertDialog(
        icon: const AppLogo(size: 48),
        title: const Text(SmartCommuteApp.title),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(description),
            const SizedBox(height: 12),
            const Text(author),
            const SizedBox(height: 4),
            Text(info?.label ?? versionUnavailable),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: SmartCommuteApp.title,
              applicationVersion: info?.label,
              applicationIcon: const AppLogo(size: 48),
            ),
            child: const Text('View licenses'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
