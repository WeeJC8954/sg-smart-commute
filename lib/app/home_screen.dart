import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../features/environment/environment_providers.dart';
import '../features/destination/presentation/destination_card.dart';
import '../features/environment/presentation/environment_dashboard.dart';
import '../features/journey/presentation/journey_card.dart';
import '../features/origin/presentation/origin_card.dart';
import 'app_logo.dart';

/// Home: rendered immediately, never blocked on location (§5.1 step 1).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(),
        actions: [
          IconButton(
            key: const Key('refresh-conditions'),
            tooltip: 'Refresh conditions',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final accepted = ref
                  .read(environmentRefresherProvider.notifier)
                  .refreshAll();
              if (!accepted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Conditions were just updated. Try again shortly.',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
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
                children: [OriginCard(), DestinationCard(), JourneyCard()],
              ),
            ),
            const SizedBox(height: 8),
            _Centred(
              maxWidth: HomeLayout.conditionsMaxWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Conditions',
                    style: Theme.of(context).textTheme.titleLarge,
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
