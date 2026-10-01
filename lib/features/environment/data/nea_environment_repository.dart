import '../../../core/config/app_config.dart';
import '../../../core/http/json_http_client.dart';
import '../../../core/time/clock.dart';
import '../domain/environment_models.dart';
import '../domain/environment_repository.dart';
import 'nea_parsers.dart';

/// data.gov.sg adapter: one GET per dataset, parsed to a nationwide snapshot.
/// Session caching lives in the Riverpod providers (one fetch per dataset).
class NeaEnvironmentRepository implements EnvironmentRepository {
  NeaEnvironmentRepository(this._http, this._clock);

  final JsonHttpClient _http;
  final Clock _clock;

  @override
  Future<ForecastSnapshot> twoHourForecast() async => parseTwoHourForecast(
    await _http.getJson(NeaEndpoints.twoHourForecast),
    fetchedAt: _clock(),
  );

  @override
  Future<UvSnapshot> uv() async =>
      parseUv(await _http.getJson(NeaEndpoints.uv), fetchedAt: _clock());

  @override
  Future<RegionalSnapshot> pm25OneHour() async =>
      parsePm25(await _http.getJson(NeaEndpoints.pm25), fetchedAt: _clock());

  @override
  Future<RegionalSnapshot> psiTwentyFourHour() async =>
      parsePsi(await _http.getJson(NeaEndpoints.psi), fetchedAt: _clock());
}
