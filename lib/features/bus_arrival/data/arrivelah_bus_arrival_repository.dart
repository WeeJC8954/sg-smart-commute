import '../../../core/config/app_config.dart';
import '../../../core/http/json_http_client.dart';
import '../domain/bus_arrival.dart';
import '../domain/bus_arrival_repository.dart';
import 'arrivelah_parser.dart';

/// [BusArrivalRepository] over ArriveLah (`arrivelah2.busrouter.sg/?id=`),
/// one request per stop. Timeouts, bounded retry and in-flight dedup come
/// from [JsonHttpClient]; caching is done by `BusArrivalCache`.
class ArriveLahBusArrivalRepository implements BusArrivalRepository {
  ArriveLahBusArrivalRepository(this._client);

  final JsonHttpClient _client;

  @override
  Future<StopArrivals> arrivalsAt(String busStopCode) async {
    final json = await _client.getJson(ArriveLahEndpoints.forStop(busStopCode));
    return parseArriveLah(json, busStopCode);
  }
}
