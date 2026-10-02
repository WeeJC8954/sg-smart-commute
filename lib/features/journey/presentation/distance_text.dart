/// A distance for display: whole metres below 1 km ("800 m"), otherwise
/// kilometres to one decimal place, without a trailing ".0" ("1.5 km", "2 km").
String distanceText(double meters) {
  final m = meters.round();
  if (m < 1000) return '$m m';
  final km = (m / 100).round() / 10;
  return km == km.roundToDouble() ? '${km.toInt()} km' : '$km km';
}
