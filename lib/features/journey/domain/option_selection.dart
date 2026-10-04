import 'direct_bus_planner.dart';

/// The user's choice among one plan's direct-bus options (P2-M3). It belongs
/// to the exact plan object it was made for: any other plan (a new journey,
/// a retried bus search) starts again at the planner's first option.
class OptionSelection {
  const OptionSelection(this.plan, this.index);

  final DirectBusOptions plan;

  /// Index into [plan]'s options.
  final int index;
}

/// The option to show for [plan]: [selection]'s index if it was made for this
/// exact plan and is in range, else 0 (the planner's suggestion).
int selectedOptionIndex(OptionSelection? selection, DirectBusOptions plan) =>
    selection != null &&
        identical(selection.plan, plan) &&
        selection.index >= 0 &&
        selection.index < plan.options.length
    ? selection.index
    : 0;
