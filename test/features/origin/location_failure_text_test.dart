// Location failure wording on Android vs Web (issue #9).
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/features/origin/presentation/origin_card.dart';

void main() {
  test('Web: "permanently denied" may also mean unavailable, and points to '
      'the site settings', () {
    final text = locationFailureText(
      const LocationPermissionPermanentlyDenied(),
      isWeb: true,
    );
    expect(text, contains('blocked or unavailable in this browser'));
    expect(text, contains("site's settings"));
  });

  test('Android keeps the domain message', () {
    expect(
      locationFailureText(
        const LocationPermissionPermanentlyDenied(),
        isWeb: false,
      ),
      const LocationPermissionPermanentlyDenied().message,
    );
  });

  test('other failures read the same on both', () {
    for (final failure in const <LocationFailure>[
      LocationPermissionDenied(),
      LocationPermissionUnanswered(),
      LocationTimeout(),
      LocationOutsideSingapore(),
    ]) {
      expect(locationFailureText(failure, isWeb: true), failure.message);
      expect(locationFailureText(failure, isWeb: false), failure.message);
    }
  });
}
