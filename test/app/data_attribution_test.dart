// A-5b: the footer's Singapore Open Data Licence notice for the arrival
// times: the source, then a link to the licence that opens it outside the app.
// C-6: the NEA and MRT sources get their own notice and link; OneMap and
// busrouter keep their credits with no licence notice.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';

import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_map.dart';
import '../../integration_test/fakes/test_app.dart';

const notice = Key('arrivals-licence-notice');
const link = Key('open-data-licence-link');

Future<void> pumpTall(WidgetTester tester, FakeLinkOpener links) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    buildTestApp(
      location: FakeLocationService(access: LocationAccess.denied),
      environment: FakeEnvironmentRepository(),
      openLink: links.call,
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the footer names the arrivals source and links the licence', (
    tester,
  ) async {
    final links = FakeLinkOpener();
    final handle = tester.ensureSemantics();
    await pumpTall(tester, links);

    final texts = tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(notice), matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .join();
    expect(
      texts,
      'Arrival times contain information from LTA DataMall (Bus Arrival), '
      'accessed through ArriveLah when shown, made available under the terms '
      'of the Singapore Open Data Licence version 1.0',
    );

    final node = tester.getSemantics(find.byKey(link));
    expect(node.flagsCollection.isLink, isTrue);
    expect(node.linkUrl, Uri.parse('https://data.gov.sg/open-data-licence'));
    expect(tester.getSize(find.byKey(link)).height, greaterThanOrEqualTo(48));

    await tester.tap(find.byKey(link));
    await tester.pump();
    expect(links.opened, [Uri.parse('https://data.gov.sg/open-data-licence')]);
    handle.dispose();
  });

  testWidgets('each open-data source has its own notice; the others none', (
    tester,
  ) async {
    final links = FakeLinkOpener();
    await pumpTall(tester, links);

    String noticeText(String key) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join();
    expect(
      noticeText('nea-licence-notice'),
      'Weather, UV and air-quality readings contain information from the '
      'National Environment Agency (NEA), accessed from data.gov.sg, made '
      'available under the terms of the Singapore Open Data Licence version 1.0',
    );
    expect(
      noticeText('mrt-licence-notice'),
      'MRT station exits contain information from the LTA MRT Station Exit '
      'dataset, accessed on 1 October 2026 from data.gov.sg, made available '
      'under the terms of the Singapore Open Data Licence version 1.0',
    );

    for (final key in ['nea-licence-link', 'mrt-licence-link']) {
      final node = tester.getSemantics(find.byKey(Key(key)));
      expect(node.flagsCollection.isLink, isTrue);
      expect(node.linkUrl, Uri.parse('https://data.gov.sg/open-data-licence'));
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
    }
    expect(links.opened, [
      Uri.parse('https://data.gov.sg/open-data-licence'),
      Uri.parse('https://data.gov.sg/open-data-licence'),
    ]);

    // OneMap and busrouter: their own credit, no licence named or linked.
    for (final credit in [
      'Place search: OneMap © Singapore Land Authority',
      'Bus data: busrouter.sg (data © LTA)',
    ]) {
      final text = find.text(credit);
      expect(text, findsOneWidget);
      expect(
        find.ancestor(of: text, matching: find.byType(Wrap)),
        findsNothing,
      );
    }
    expect(find.textContaining('Data: '), findsNothing);
  });

  testWidgets('a screen reader hears each notice, then its own link', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpTall(tester, FakeLinkOpener());

    for (final (noticeKey, linkKey, source) in [
      ('nea-licence-notice', 'nea-licence-link', 'National Environment'),
      ('mrt-licence-notice', 'mrt-licence-link', 'MRT Station Exit'),
      ('arrivals-licence-notice', 'open-data-licence-link', 'LTA DataMall'),
    ]) {
      // Its own node, labelled with this source only (not merged with the
      // other credits), and the link inside it, so each link is read in context.
      final group = tester.getSemantics(find.byKey(Key(noticeKey)));
      expect(group.label, contains(source));
      expect(group.label, isNot(contains('OneMap')));
      expect(group.label.split('contain information').length, 2);
      expect(group.flagsCollection.isLink, isFalse);
      // The link is a node of its own, named by the licence only.
      final linkNode = tester.getSemantics(find.byKey(Key(linkKey)));
      expect(linkNode, isNot(same(group)));
      expect(linkNode.label, 'Singapore Open Data Licence version 1.0');
      expect(linkNode.flagsCollection.isLink, isTrue);
      SemanticsNode? up = linkNode.parent;
      while (up != null && up != group) {
        up = up.parent;
      }
      expect(up, same(group), reason: '$linkKey inside $noticeKey');
    }
    handle.dispose();
  });

  testWidgets('a licence link that cannot be opened only shows a note', (
    tester,
  ) async {
    await pumpTall(tester, FakeLinkOpener(result: false));
    await tester.tap(find.byKey(link));
    await tester.pump();
    expect(find.text("Couldn't open data.gov.sg."), findsOneWidget);
    expect(find.byKey(notice), findsOneWidget);
  });
}
