import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';

/// Creates the tile provider for one opened map. Tests override it with a
/// fake, so they never fetch tiles.
typedef MapTileProviderFactory = TileProvider Function();

final mapTileProviderFactoryProvider = Provider<MapTileProviderFactory>(
  (ref) => OneMapTileProvider.new,
);

/// The OneMap logo shown in the attribution. Injectable for tests.
final mapLogoImageProvider = Provider<ImageProvider>(
  (ref) => NetworkImage(BasemapEndpoints.logo.toString()),
);

/// Opens an attribution link in the external browser; false if it could not
/// be opened. Injectable for tests (no browser is ever opened by a test).
final mapLinkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// The OneMap style for [brightness]: Default (light) or Night (dark).
String basemapTemplateFor(Brightness brightness) => switch (brightness) {
  Brightness.light => BasemapEndpoints.defaultTiles,
  Brightness.dark => BasemapEndpoints.nightTiles,
};

/// OneMap tiles over plain HTTP: no automatic retry (flutter_map's default
/// client retries failed requests), and on Android a size-capped built-in
/// cache that follows the tiles' `Cache-Control`. Its client is closed when
/// the map is closed.
class OneMapTileProvider extends NetworkTileProvider {
  OneMapTileProvider() : this._(http.Client());

  OneMapTileProvider._(this._client)
    : super(
        httpClient: _client,
        cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
          maxCacheSize: MapConfig.tileCacheMaxBytes,
        ),
      );

  final http.Client _client;

  @override
  Future<void> dispose() async {
    await super.dispose();
    _client.close();
  }
}

/// The attribution OneMap requires whenever its tiles are shown
/// (docs/map-feasibility.md §4.2): the logo, then "OneMap © contributors |
/// Singapore Land Authority", with both names linked. Always visible: it is
/// never collapsed or drawn over the map.
class BasemapAttributionRow extends ConsumerWidget {
  const BasemapAttributionRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      key: const Key('basemap-attribution'),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Image(
          image: ref.watch(mapLogoImageProvider),
          width: 20,
          height: 20,
          semanticLabel: 'OneMap logo',
          // A missing logo must not take the attribution text with it.
          errorBuilder: (_, _, _) => const SizedBox.square(dimension: 20),
        ),
        const SizedBox(width: 4),
        _AttributionLink(
          BasemapAttribution.oneMap,
          BasemapEndpoints.oneMapSite,
          key: const Key('attribution-onemap'),
        ),
        Text(BasemapAttribution.contributors, style: style),
        _AttributionLink(
          BasemapAttribution.sla,
          BasemapEndpoints.slaSite,
          key: const Key('attribution-sla'),
        ),
      ],
    );
  }
}

class _AttributionLink extends ConsumerWidget {
  const _AttributionLink(this.label, this.uri, {super.key});

  final String label;
  final Uri uri;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    bool opened;
    try {
      opened = await ref.read(mapLinkOpenerProvider)(uri);
    } catch (_) {
      opened = false;
    }
    // Only a note: a link that won't open never affects the map or journey.
    if (!opened) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text("Couldn't open ${uri.host}.")));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Semantics(
      link: true,
      linkUrl: uri,
      child: InkWell(
        onTap: () => _open(context, ref),
        child: ConstrainedBox(
          // A comfortable touch target for a short text link.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Align(
              widthFactor: 1,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
