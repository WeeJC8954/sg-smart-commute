// Map tiles drawn on the device, with no network request: the README
// screenshot generator (integration_test/demo/readme_screenshots.dart) and
// the map performance probe (tool/map_performance_probe.dart) use them
// instead of OneMap's tiles.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';

/// Map tiles drawn on the device: an invented street grid with parks and
/// water, light for the Default style and dark for Night. Not a map of
/// anywhere; nothing is fetched.
class SyntheticTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates c, TileLayer options) =>
      _SyntheticTile(
        c.x,
        c.y,
        c.z,
        options.urlTemplate == BasemapEndpoints.nightTiles,
      );
}

@immutable
class _SyntheticTile extends ImageProvider<_SyntheticTile> {
  const _SyntheticTile(this.x, this.y, this.z, this.dark);

  final int x, y, z;
  final bool dark;

  @override
  Future<_SyntheticTile> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _SyntheticTile key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_draw());

  Future<ImageInfo> _draw() async {
    const size = 256.0;
    final land = Color(dark ? 0xFF1E2328 : 0xFFF2EFE9);
    final park = Color(dark ? 0xFF233629 : 0xFFCFE7C8);
    final water = Color(dark ? 0xFF16283A : 0xFFAAD3DF);
    final minor = Color(dark ? 0xFF2F353D : 0xFFFFFFFF);
    final major = Color(dark ? 0xFF46505B : 0xFFFAD98A);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(land, BlendMode.src);

    // Blocks a fixed number of world pixels apart at z13, scaled to this zoom,
    // so streets line up across tiles and zoom levels.
    final block = 72 * math.pow(2, z - 13).toDouble();
    final ox = x * size, oy = y * size;
    final first = (ox / block).floor(), firstY = (oy / block).floor();
    for (var i = first; i * block < ox + size; i++) {
      for (var j = firstY; j * block < oy + size; j++) {
        final h = (i * 73856093) ^ (j * 19349663);
        final fill = h % 29 == 0 ? water : (h % 11 == 0 ? park : null);
        if (fill != null) {
          canvas.drawRect(
            Rect.fromLTWH(i * block - ox, j * block - oy, block, block),
            Paint()..color = fill,
          );
        }
      }
    }
    final w = (block / 12).clamp(1.0, 14.0);
    for (var i = first; i * block < ox + size + block; i++) {
      final isMajor = i % 4 == 0;
      canvas.drawRect(
        Rect.fromLTWH(i * block - ox - w / 2, 0, isMajor ? w * 1.8 : w, size),
        Paint()..color = isMajor ? major : minor,
      );
    }
    for (var j = firstY; j * block < oy + size + block; j++) {
      final isMajor = j % 4 == 0;
      canvas.drawRect(
        Rect.fromLTWH(0, j * block - oy - w / 2, size, isMajor ? w * 1.8 : w),
        Paint()..color = isMajor ? major : minor,
      );
    }
    final image = await recorder.endRecording().toImage(256, 256);
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) =>
      other is _SyntheticTile &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.dark == dark;

  @override
  int get hashCode => Object.hash(x, y, z, dark);
}
