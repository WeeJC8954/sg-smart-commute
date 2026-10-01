import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../environment/domain/environment_models.dart';
import '../../environment/environment_providers.dart';
import '../domain/origin.dart';
import '../domain/origin_controller.dart';

/// Origin status, the manual-origin prompt and the late-fix offer (§5.1–§5.4).
class OriginCard extends ConsumerWidget {
  const OriginCard({super.key});

  static const String fallbackPrompt =
      "We couldn't determine your location. Where are you now?";

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(originControllerProvider);
    final controller = ref.read(originControllerProvider.notifier);
    final theme = Theme.of(context);

    final children = <Widget>[];
    switch (state.phase) {
      case OriginPhase.checkingPermission:
        children.add(const _Busy('Checking location permission…'));
      case OriginPhase.acquiring:
        children.add(const _Busy('Finding your location…'));
      case OriginPhase.ready:
        children.add(_OriginLine(origin: state.origin!));
        children.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: controller.changeOrigin,
              child: const Text('Change'),
            ),
          ),
        );
      case OriginPhase.needsManual:
        final reason = state.fallbackReason;
        if (reason != null) {
          children
            ..add(Text(fallbackPrompt, style: theme.textTheme.titleMedium))
            ..add(Text(reason.message))
            ..add(_FallbackActions(reason: reason));
        } else {
          children.add(
            Text('Where are you now?', style: theme.textTheme.titleMedium),
          );
          if (state.origin != null) {
            children.add(_OriginLine(origin: state.origin!));
          }
        }
        children.add(const SizedBox(height: 8));
        children.add(const ManualOriginPicker());
    }

    if (state.offeredGpsFix != null) {
      children.add(
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            key: const Key('use-current-location'),
            avatar: const Icon(Icons.my_location, size: 18),
            label: const Text('Use my current location'),
            onPressed: controller.useCurrentLocation,
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _OriginLine extends StatelessWidget {
  const _OriginLine({required this.origin});
  final Origin origin;

  @override
  Widget build(BuildContext context) {
    final how = switch (origin.provenance) {
      OriginProvenance.gps => 'from GPS',
      OriginProvenance.manual => 'chosen manually',
    };
    return Row(
      children: [
        Icon(
          origin.provenance == OriginProvenance.gps
              ? Icons.my_location
              : Icons.place_outlined,
          size: 20,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'From: ${origin.label} ($how)',
            key: const Key('origin-line'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

class _FallbackActions extends ConsumerWidget {
  const _FallbackActions({required this.reason});
  final LocationFailure reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(originControllerProvider.notifier);
    final canOpenSettings =
        !kIsWeb &&
        (reason is LocationPermissionPermanentlyDenied ||
            reason is LocationServiceDisabled);
    return Wrap(
      spacing: 8,
      children: [
        if (canOpenSettings)
          TextButton(
            onPressed: controller.openSettings,
            child: const Text('Open settings'),
          ),
        TextButton(
          onPressed: controller.retryLocation,
          child: const Text('Try location again'),
        ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        ExcludeSemantics(child: Text(label)),
      ],
    ),
  );
}

/// Milestone 1 manual origin: choose one of the NEA two-hour forecast areas
/// (the ~47 names and label locations in the live payload). Milestone 2
/// replaces this with place search (§5.3). See docs/assumptions.md.
class ManualOriginPicker extends ConsumerStatefulWidget {
  const ManualOriginPicker({super.key});

  static const int maxResults = 8;

  @override
  ConsumerState<ManualOriginPicker> createState() => _ManualOriginPickerState();
}

class _ManualOriginPickerState extends ConsumerState<ManualOriginPicker> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) _beginEntry();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _beginEntry() =>
      ref.read(originControllerProvider.notifier).beginManualEntry();

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(forecastSnapshotProvider);
    if (areas.isLoading && !areas.hasValue) {
      return const _Busy('Loading areas…');
    }
    if (areas.hasError && !areas.isLoading) {
      final failure = areas.error;
      return Row(
        children: [
          Expanded(
            child: Text(
              'Area list unavailable. '
              '${failure is AppFailure ? failure.message : ''}',
            ),
          ),
          TextButton(
            onPressed: () => ref.invalidate(forecastSnapshotProvider),
            child: const Text('Retry'),
          ),
        ],
      );
    }

    final query = _controller.text.trim().toLowerCase();
    final all = areas.requireValue.areas;
    final matches = query.isEmpty
        ? const <ForecastArea>[]
        : all
              .where((a) => a.name.toLowerCase().contains(query))
              .take(ManualOriginPicker.maxResults)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('manual-origin-field'),
          controller: _controller,
          focusNode: _focus,
          decoration: const InputDecoration(
            labelText: 'Your area',
            hintText: 'e.g. Bishan, Tampines, City, Jurong East',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (_) {
            _beginEntry();
            setState(() {});
          },
        ),
        if (query.isNotEmpty && matches.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No matching area. Try a nearby town name.'),
          ),
        for (final area in matches)
          ListTile(
            key: Key('area-${area.name}'),
            leading: const Icon(Icons.place_outlined),
            title: Text(area.name),
            subtitle: const Text('NEA forecast area'),
            onTap: () {
              ref
                  .read(originControllerProvider.notifier)
                  .selectManualOrigin('${area.name} area', area.location);
              _controller.clear();
              _focus.unfocus();
            },
          ),
      ],
    );
  }
}
