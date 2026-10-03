import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/ui/motion.dart';
import '../core/ui/section_heading.dart';
import '../features/environment/environment_providers.dart';
import '../features/environment/presentation/environment_dashboard.dart';
import '../features/journey/presentation/journey_card.dart';
import '../features/map/presentation/journey_map_card.dart';
import 'app_logo.dart';
import 'route_card.dart';

/// Home: rendered immediately, never blocked on location (§5.1 step 1).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle()),
      body: SafeArea(
        // The list spans the window (so it scrolls from anywhere); each
        // section is centred at its own maximum width.
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const _Centred(
              maxWidth: HomeLayout.contentMaxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RouteCard(),
                  MotionSize(child: JourneyCard()),
                  JourneyMapCard(),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _Centred(
              maxWidth: HomeLayout.conditionsMaxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SectionHeading(
                          'Conditions',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const _RefreshConditionsButton(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const EnvironmentDashboard(),
                  const SizedBox(height: 12),
                  Text(
                    'Data: $neaSourceLabel (Singapore Open Data Licence) · '
                    '$oneMapAttribution · $busrouterAttribution · '
                    '$arriveLahAttribution · $mrtAttribution',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [child] at most [maxWidth] wide, centred in the list.
class _Centred extends StatelessWidget {
  const _Centred({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Refreshes the four Conditions datasets (with the cooldown in
/// [EnvironmentRefresher]). It sits beside the heading of what it
/// refreshes; the tiles' own spinners show the progress right below it.
class _RefreshConditionsButton extends ConsumerWidget {
  const _RefreshConditionsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    key: const Key('refresh-conditions'),
    tooltip: 'Refresh conditions',
    icon: const Icon(Icons.refresh),
    onPressed: () {
      final note = switch (ref
          .read(environmentRefresherProvider.notifier)
          .refreshAll()) {
        RefreshAllResult.started => null,
        RefreshAllResult.stillRefreshing => 'Conditions are still refreshing.',
        RefreshAllResult.justUpdated =>
          'Conditions were just updated. Try again shortly.',
      };
      if (note != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(note)));
      }
    },
  );
}
