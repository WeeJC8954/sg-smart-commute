import 'environment_models.dart';

/// Source of the four nationwide NEA datasets (§6). Implementations throw
/// typed `AppFailure`s only.
abstract interface class EnvironmentRepository {
  Future<ForecastSnapshot> twoHourForecast();
  Future<UvSnapshot> uv();
  Future<RegionalSnapshot> pm25OneHour();
  Future<RegionalSnapshot> psiTwentyFourHour();
}
