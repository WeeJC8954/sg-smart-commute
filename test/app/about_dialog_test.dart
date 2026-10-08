// E4: the app-bar About action and its dialog. Opening and closing it
// changes nothing else in the app.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/about_dialog.dart';
import 'package:sg_smart_commute/app/app.dart';
import 'package:sg_smart_commute/app/app_info.dart';
import 'package:sg_smart_commute/app/app_logo.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';

import '../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../integration_test/fakes/fake_bus_network.dart';
import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_map.dart';
import '../../integration_test/fakes/fake_place_search_repository.dart';
import '../../integration_test/fakes/fake_route_geometry.dart';
import '../../integration_test/fakes/test_app.dart';

const aboutButton = Key('about-button');
const dialogTransition = Duration(milliseconds: 300);
const bishan = LatLng(1.3508, 103.8485);

Widget app({
  AppInfo? appInfo = fakeAppInfo,
  AppPalette palette = AppPalette.teal,
}) => buildTestApp(
  location: FakeLocationService(access: LocationAccess.denied),
  environment: FakeEnvironmentRepository(),
  appInfo: appInfo,
  palette: palette,
);

Future<void> pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pump();
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.byKey(aboutButton));
  await tester.pump();
  await tester.pump(dialogTransition);
}

Future<void> settleDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(dialogTransition);
}

/// The dialog's texts in tree (reading) order.
List<String?> dialogTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .toList();

bool aboutFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var found = context.widget.key == aboutButton;
  context.visitAncestorElements((e) {
    found = found || e.widget.key == aboutButton;
    return !found;
  });
  return found;
}

/// Android's system Back, as the engine delivers it.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      const MethodCall('popRoute'),
    ),
    (_) {},
  );
}

void main() {
  testWidgets('a named button before the colour theme button; the logo and '
      'title stay decorative', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTall(tester, app());
    expect(
      tester.getSemantics(find.byKey(aboutButton)),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        tooltip: 'About Singapore Smart Commute',
      ),
    );
    expect(
      tester.getRect(find.byKey(aboutButton)).right,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('palette-button'))).left,
      ),
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('app-logo')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(SmartCommuteApp.title),
        ),
      ),
      isNot(isSemantics(hasTapAction: true)),
    );
    semantics.dispose();
  });

  testWidgets('opens by tap: icon, name, description, author, the '
      'compiled-in version, then View licenses and Close; no build date', (
    tester,
  ) async {
    await pumpTall(tester, app());
    await open(tester);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(AppLogo),
      ),
      findsOneWidget,
    );
    expect(dialogTexts(tester), [
      'Singapore Smart Commute',
      AboutAppDialog.description,
      'Author: Jaycee Wee',
      'Version 9.8.7 (42)',
      'View licenses',
      'Close',
    ]);
  });

  testWidgets('the dialog node itself is named "Singapore Smart Commute" and '
      'names its route', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTall(tester, app());
    await open(tester);
    expect(
      tester.getSemantics(find.byType(Dialog)),
      isSemantics(
        role: SemanticsRole.alertDialog,
        label: SmartCommuteApp.title,
        namesRoute: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('a build without a version: "Version unavailable", the rest '
      'unchanged', (tester) async {
    await pumpTall(tester, app(appInfo: null));
    await open(tester);
    expect(dialogTexts(tester), [
      'Singapore Smart Commute',
      AboutAppDialog.description,
      'Author: Jaycee Wee',
      'Version unavailable',
      'View licenses',
      'Close',
    ]);
  });

  testWidgets('Close, Escape and system Back each close it', (tester) async {
    await pumpTall(tester, app());
    await open(tester);
    await tester.tap(find.text('Close'));
    await settleDialog(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleDialog(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await open(tester);
    await systemBack(tester);
    await settleDialog(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget, reason: 'app still open');
  });

  testWidgets(
    'keyboard: Tab reaches About first; Enter opens; Escape closes and '
    'returns focus; Space opens',
    (tester) async {
      await pumpTall(tester, app());
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(aboutFocused(), isTrue, reason: 'the first Tab stop');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleDialog(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleDialog(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(aboutFocused(), isTrue, reason: 'focus returns to the button');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settleDialog(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets("View licenses opens Flutter's licence page", (tester) async {
    await pumpTall(tester, app());
    await open(tester);
    await tester.tap(find.text('View licenses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('360 × 780 dp at 2× text: both actions fit beside the title; '
      'the dialog scrolls and its buttons stay on screen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(tester.takeException(), isNull);
    final about = tester.getRect(find.byKey(aboutButton));
    final palette = tester.getRect(find.byKey(const Key('palette-button')));
    expect(about.width, greaterThanOrEqualTo(48));
    expect(about.right, lessThanOrEqualTo(palette.left));
    expect(
      tester
          .getRect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(SmartCommuteApp.title),
            ),
          )
          .right,
      lessThanOrEqualTo(about.left),
    );
    await open(tester);
    expect(tester.takeException(), isNull);
    final screen = Offset.zero & const Size(360, 780);
    for (final label in ['View licenses', 'Close']) {
      final r = tester.getRect(find.text(label));
      expect(
        screen.contains(r.topLeft) &&
            screen.contains(r.bottomRight - const Offset(1, 1)),
        isTrue,
        reason: label,
      );
    }
    await tester.scrollUntilVisible(
      find.text('Version 9.8.7 (42)'),
      50,
      scrollable: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  for (final b in Brightness.values) {
    for (final p in AppPalette.values) {
      testWidgets(
        '${b.name}, ${p.label}: the dialog takes the palette scheme',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = b;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          await pumpTall(tester, app(palette: p));
          await open(tester);
          expect(tester.takeException(), isNull);
          expect(
            Theme.of(tester.element(find.byType(AlertDialog))).colorScheme,
            paletteTheme(p, b).colorScheme,
          );
        },
      );
    }
  }

  testWidgets('opening and closing About changes nothing else: no re-plan, '
      'refetch, camera move, tile or geometry request; the selection kept', (
    tester,
  ) async {
    final bus = FakeBusNetworkRepository();
    final arrivals = FakeBusArrivalRepository();
    final geometry = FakeRouteGeometryRepository();
    final tiles = FakeTileProvider();
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: bishan,
        ),
        environment: FakeEnvironmentRepository(),
        places: FakePlaceSearchRepository(),
        busNetwork: bus,
        busArrivals: arrivals,
        routeGeometry: geometry,
        mapTiles: () => tiles,
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('destination-field')),
      'VivoCity',
    );
    await tester.pump(pastSearchDebounce);
    await tester.pump();
    await tester.tap(find.text('VIVOCITY'));
    await tester.pump();
    await tester.pump();
    for (final key in ['select-option-F10', 'show-map']) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pump();
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      await tester.pump();
    }
    Object? plan() =>
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
            .read(journeyPlanProvider)
            .value;
    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(MarkerLayer)));
    final before = (
      plan: plan(),
      centre: camera().center,
      zoom: camera().zoom,
      loads: (bus.loads, arrivals.totalCalls, geometry.loads),
      tiles: tiles.requested.length,
    );
    expect(before.plan, isNotNull);
    expect(before.tiles, greaterThan(0), reason: 'the map really drew');

    await open(tester);
    await tester.tap(find.text('Close'));
    await settleDialog(tester);

    expect(identical(plan(), before.plan), isTrue, reason: '0 new plans');
    expect(camera().center, before.centre);
    expect(camera().zoom, before.zoom);
    expect((bus.loads, arrivals.totalCalls, geometry.loads), before.loads);
    expect(tiles.requested.length, before.tiles);
    expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
  });
}
