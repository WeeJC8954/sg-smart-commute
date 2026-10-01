import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../features/environment/environment_providers.dart';
import '../features/environment/presentation/environment_dashboard.dart';
import '../features/origin/presentation/origin_card.dart';
import 'app.dart';

/// Home: rendered immediately, never blocked on location (§5.1 step 1).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(SmartCommuteApp.title),
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const OriginCard(),
                const SizedBox(height: 8),
                Text(
                  'Conditions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const EnvironmentDashboard(),
                const SizedBox(height: 12),
                Text(
                  'Data: $neaSourceLabel (Singapore Open Data Licence)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
