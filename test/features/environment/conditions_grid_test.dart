// The Conditions tiles as a responsive grid: 2 × 2 on phones, one column when
// narrow or with large text, four across on wide Web. Presentation only: the
// fakes and providers are the same as in test/widget_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/config/app_config.dart';
import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/environment/presentation/environment_dashboard.dart';
import 'package:sg_smart_commute/features/environment/presentation/reading_text.dart';

import '../../../integration_test/fakes/fake_environment_repository.dart';
import '../../../integration_test/fakes/fake_location_service.dart';
import '../../../integration_test/fakes/test_app.dart';

const bishan = LatLng(1.3508, 103.8485);
const tileKeys = ['tile-forecast', 'tile-uv', 'tile-pm25', 'tile-psi'];

Finder tile(String key) => find.byKey(Key(key));
Finder inTile(String key, String text) =>
    find.descendant(of: tile(key), matching: find.text(text));
Rect rectOf(WidgetTester tester, String key) => tester.getRect(tile(key));

void main() {
  late FakeEnvironmentRepository env;

  setUp(() => env = FakeEnvironmentRepository());

  Future<void> pumpAt(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
    Duration? clockOffset,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: bishan,
        ),
        environment: env,
        clock: clockOffset == null ? null : () => fakeNow.add(clockOffset),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Scrolls the grid into view (the cards above it come first).
  Future<void> showGrid(WidgetTester tester) async {
    await tester.ensureVisible(tile('tile-forecast'));
    await tester.pump();
  }

  group('conditionsColumns', () {
    const gap = HomeLayout.gridGap;
    final twoUp = 2 * HomeLayout.minTileWidth + gap; // 308
    final fourUp = 4 * HomeLayout.minWideTileWidth + 3 * gap; // 904

    test('phone widths → 2, narrow → 1, wide → 4', () {
      expect(conditionsColumns(336, 1), 2); // 360 dp phone minus padding
      expect(conditionsColumns(388, 1), 2); // 412 dp phone
      expect(conditionsColumns(twoUp, 1), 2);
      expect(conditionsColumns(twoUp - 1, 1), 1);
      expect(conditionsColumns(296, 1), 1); // 320 dp phone
      expect(conditionsColumns(fourUp - 1, 1), 2);
      expect(conditionsColumns(fourUp, 1), 4);
      expect(conditionsColumns(1080, 1), 4);
    });

    test('larger text needs more room per tile', () {
      expect(conditionsColumns(388, 1.3), 1); // 2 × 195 + 8 > 388
      expect(conditionsColumns(388, 1.15), 2);
      expect(conditionsColumns(1080, 1.3), 2); // 4 across would need 1168
      expect(conditionsColumns(336, 0.85), 2); // never denser than at 1.0
    });
  });

  testWidgets('normal phone (360 dp): a 2 × 2 grid in reading order, rows '
      'of equal height', (tester) async {
    await pumpAt(tester, const Size(360, 800));
    await showGrid(tester);
    expect(find.byKey(const Key('conditions-grid-2')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final f = rectOf(tester, 'tile-forecast');
    final uv = rectOf(tester, 'tile-uv');
    final pm = rectOf(tester, 'tile-pm25');
    final psi = rectOf(tester, 'tile-psi');
    // Row 1: Weather, UV. Row 2: 1-hr PM2.5, 24-hr PSI.
    expect(uv.top, f.top);
    expect(uv.left, greaterThan(f.right));
    expect(psi.top, pm.top);
    expect(pm.top, greaterThan(f.bottom));
    expect(pm.left, f.left);
    expect(uv.height, f.height);
    expect(psi.height, pm.height);
    expect(f.width, closeTo(uv.width, 0.5));
  });

  testWidgets('every tile keeps its scope, value, category and timestamp in '
      'the 2 × 2 grid', (tester) async {
    await pumpAt(tester, const Size(360, 800));
    await showGrid(tester);
    expect(inTile('tile-forecast', 'Partly Cloudy (Day)'), findsOneWidget);
    expect(inTile('tile-forecast', 'Bishan area'), findsOneWidget);
    expect(inTile('tile-uv', '7'), findsOneWidget);
    expect(inTile('tile-uv', 'High'), findsOneWidget);
    expect(inTile('tile-uv', 'Singapore (national)'), findsOneWidget);
    expect(inTile('tile-pm25', '18 µg/m³'), findsOneWidget);
    expect(inTile('tile-pm25', 'Normal'), findsOneWidget);
    expect(inTile('tile-pm25', 'Central region'), findsOneWidget);
    expect(inTile('tile-psi', '54'), findsOneWidget);
    expect(inTile('tile-psi', 'Moderate'), findsOneWidget);
    expect(inTile('tile-psi', 'As of 12:00 SGT · 12 min ago'), findsOneWidget);
    expect(find.text('Out of date'), findsNothing);
  });

  testWidgets('stale, failed-with-Retry and failed-refresh states in the '
      '2 × 2 grid; Retry stays per dataset', (tester) async {
    env.failPsi = const NetworkUnavailable();
    await pumpAt(
      tester,
      const Size(360, 800),
      clockOffset: const Duration(hours: 3),
    );
    await showGrid(tester);
    expect(tester.takeException(), isNull);
    expect(inTile('tile-pm25', 'Out of date'), findsOneWidget);
    expect(
      inTile('tile-psi', const NetworkUnavailable().message),
      findsOneWidget,
    );

    env.failPsi = null;
    final retry = find.descendant(
      of: tile('tile-psi'),
      matching: find.text('Retry'),
    );
    await tester.ensureVisible(retry);
    await tester.pump();
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    expect(inTile('tile-psi', '54'), findsOneWidget);
    expect(inTile('tile-psi', 'Moderate'), findsOneWidget);
    expect(env.calls['psi'], 2);
    expect(env.calls['pm25'], 1);
  });

  testWidgets('loading and waiting-for-location states fit a 2 × 2 tile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(), // permission never answered
        environment: env,
      ),
    );
    // First frame: every dataset still loading.
    expect(find.text('Loading 24-hr PSI…'), findsOneWidget);
    expect(find.byKey(const Key('conditions-grid-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(inTile('tile-psi', 'Waiting for your location'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow phone (300 dp): one column', (tester) async {
    await pumpAt(tester, const Size(300, 900));
    await showGrid(tester);
    expect(find.byKey(const Key('conditions-grid-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    final rects = [for (final k in tileKeys) rectOf(tester, k)];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, rects[0].left);
      expect(rects[i].top, greaterThan(rects[i - 1].bottom));
    }
  });

  testWidgets('large text on a normal phone: one column', (tester) async {
    await pumpAt(tester, const Size(412, 900), textScale: 1.5);
    await showGrid(tester);
    expect(find.byKey(const Key('conditions-grid-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide Web (1280 px): four across, wider than the cards above', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1280, 900));
    await showGrid(tester);
    expect(find.byKey(const Key('conditions-grid-4')), findsOneWidget);
    final rects = [for (final k in tileKeys) rectOf(tester, k)];
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top, rects[0].top);
      expect(rects[i].left, greaterThan(rects[i - 1].right));
    }
    final gridWidth = rects.last.right - rects.first.left;
    expect(gridWidth, closeTo(HomeLayout.conditionsMaxWidth, 1));
    final originCard = tester.getRect(find.byType(Card).first);
    expect(originCard.width, closeTo(HomeLayout.contentMaxWidth, 1));
  });

  testWidgets('tablet / mid Web width (720 px): 2 × 2', (tester) async {
    await pumpAt(tester, const Size(720, 900));
    await showGrid(tester);
    expect(find.byKey(const Key('conditions-grid-2')), findsOneWidget);
  });
  testWidgets('a tile shows its label once and its number large', (
    tester,
  ) async {
    await pumpAt(tester, const Size(360, 800));
    await showGrid(tester);
    expect(inTile('tile-psi', ReadingText.psiTitle), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('tile-psi')),
        matching: find.textContaining('24-hr PSI 54'),
      ),
      findsNothing,
    );
    final value = tester.widget<Text>(inTile('tile-psi', '54'));
    final body = Theme.of(tester.element(inTile('tile-psi', '54')))
        .textTheme
        .bodyMedium!;
    expect(value.style!.fontSize, greaterThan(body.fontSize!));
  });

  testWidgets('screen readers hear label, value, band, scope and time', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpAt(tester, const Size(360, 800));
    await showGrid(tester);
    final label = tester.getSemantics(find.byKey(const Key('tile-psi'))).label;
    for (final part in [
      '24-hr PSI',
      '54',
      'Moderate',
      'Central region',
      'As of 12:00 SGT',
    ]) {
      expect(label, contains(part));
    }
    // The label comes before the value.
    expect(label.indexOf('24-hr PSI'), lessThan(label.indexOf('54')));
    semantics.dispose();
  });
}
