import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/mrt.dart';
import 'mrt_asset.dart';

/// The bundled MRT station asset (guide v2.1 §9.5). Read once per session.
/// A missing or malformed asset is [StaticDataUnavailable].
class MrtAssetRepository {
  MrtAssetRepository({Future<String> Function()? load})
    : _load = load ?? (() => rootBundle.loadString(mrtStationsAsset));

  final Future<String> Function() _load;
  Future<List<MrtStation>>? _stations;

  Future<List<MrtStation>> stations() {
    final existing = _stations;
    if (existing != null) return existing;
    final loading = _read();
    _stations = loading;
    loading.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_stations, loading)) _stations = null;
      },
    );
    return loading;
  }

  Future<List<MrtStation>> _read() async {
    final String text;
    try {
      text = await _load();
    } catch (e) {
      throw StaticDataUnavailable(
        StaticDataset.mrtStations,
        'asset not loaded: $e',
      );
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const StaticDataUnavailable(StaticDataset.mrtStations, 'not JSON');
    }
    return parseMrtAsset(json);
  }
}
