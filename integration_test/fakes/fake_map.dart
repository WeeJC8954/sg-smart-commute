import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// A 1 × 1 transparent PNG: the fake tiles and the fake OneMap logo.
final Uint8List transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Tiles without a network: blank, or (with [fail]) every tile fails, as when
/// OneMap is unreachable. Records each tile the map asked for, so tests can
/// prove when tiles are (and are not) requested.
class FakeTileProvider extends TileProvider {
  FakeTileProvider({this.fail = false});

  final bool fail;
  final List<TileCoordinates> requested = [];
  bool disposed = false;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requested.add(coordinates);
    return fail ? const _UnavailableTile() : MemoryImage(transparentPng);
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _UnavailableTile extends ImageProvider<_UnavailableTile> {
  const _UnavailableTile();

  @override
  Future<_UnavailableTile> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _UnavailableTile key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future.error(StateError('tile unavailable (fake)')),
  );
}

/// Records attribution links instead of opening a browser; [result] is what
/// the launcher reports.
class FakeLinkOpener {
  FakeLinkOpener({this.result = true});

  bool result;
  final List<Uri> opened = [];

  Future<bool> call(Uri uri) async {
    opened.add(uri);
    return result;
  }
}
