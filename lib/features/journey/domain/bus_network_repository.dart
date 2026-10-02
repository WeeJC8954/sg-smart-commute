import 'bus_network.dart';

/// Static bus data source (guide v2.1 §9.1). busrouter today; replaceable.
abstract interface class BusNetworkRepository {
  /// The whole network, loaded once per session. Throws
  /// `StaticDataUnavailable` if it cannot be loaded or validated.
  Future<BusNetwork> load();
}
