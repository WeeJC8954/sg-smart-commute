/// A distance for display. The value is rounded to whole metres first: below
/// 1000 m it shows as metres ("800 m"), otherwise as kilometres to one decimal
/// place, without a trailing ".0" ("1.5 km", "2 km"). So 999.5–999.9 m rounds
/// to 1000 m and shows as "1 km", never "1000 m".
String distanceText(double meters) {
  final m = meters.round();
  if (m < 1000) return '$m m';
  final km = (m / 100).round() / 10;
  return km == km.roundToDouble() ? '${km.toInt()} km' : '$km km';
}
