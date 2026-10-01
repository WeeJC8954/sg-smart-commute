/// Official NEA band tables (guide §6.1; sources cited in docs/data-sources.md).
/// Bands are always shown as text, never by colour alone (§7).
library;

/// 24-hr PSI descriptor (haze.gov.sg).
String? psiBand(num psi) {
  if (psi < 0) return null;
  if (psi <= 50) return 'Good';
  if (psi <= 100) return 'Moderate';
  if (psi <= 200) return 'Unhealthy';
  if (psi <= 300) return 'Very unhealthy';
  return 'Hazardous';
}

/// 1-hr PM2.5 band descriptor in µg/m³ (haze.gov.sg: Band I–IV).
String? pm25Band(num pm25) {
  if (pm25 < 0) return null;
  if (pm25 <= 55) return 'Normal';
  if (pm25 <= 150) return 'Elevated';
  if (pm25 <= 250) return 'High';
  return 'Very high';
}

/// UV index exposure category (nea.gov.sg).
String? uvBand(num uv) {
  if (uv < 0) return null;
  if (uv <= 2) return 'Low';
  if (uv <= 5) return 'Moderate';
  if (uv <= 7) return 'High';
  if (uv <= 10) return 'Very high';
  return 'Extreme';
}
