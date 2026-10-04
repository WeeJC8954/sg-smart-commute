// P2-M3: the selected direct-bus option belongs to the exact plan object it
// was made for, so a selection can never leak into a new journey.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/option_selection.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';

import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';

const bishan = LatLng(1.3508, 103.8485);

/// Bishan → VivoCity on the fake network: F20 (suggested), F10, F30.
DirectBusOptions vivoPlan() =>
    planDirectBus(fakeBusNetwork(), bishan, vivoCity.position)
        as DirectBusOptions;

void main() {
  test("no selection → the planner's first option", () {
    expect(selectedOptionIndex(null, vivoPlan()), 0);
  });

  test('a selection applies only to the exact plan object it was made for', () {
    final a = vivoPlan(), b = vivoPlan(); // equal content, different objects
    final selection = OptionSelection(a, 2);
    expect(selectedOptionIndex(selection, a), 2);
    expect(selectedOptionIndex(selection, b), 0);
  });

  test('an out-of-range index → 0', () {
    final a = vivoPlan();
    expect(selectedOptionIndex(OptionSelection(a, 3), a), 0);
    expect(selectedOptionIndex(OptionSelection(a, -1), a), 0);
  });

  test('select() stores the choice; an out-of-range select is ignored', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final a = vivoPlan();
    c.read(optionSelectionProvider.notifier).select(a, 1);
    expect(selectedOptionIndex(c.read(optionSelectionProvider), a), 1);
    c.read(optionSelectionProvider.notifier).select(a, 5);
    expect(c.read(optionSelectionProvider)!.index, 1);
  });

  test('selecting never creates or reads the plan provider', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(optionSelectionProvider.notifier).select(vivoPlan(), 1);
    expect(c.exists(journeyPlanProvider), isFalse);
  });
}
