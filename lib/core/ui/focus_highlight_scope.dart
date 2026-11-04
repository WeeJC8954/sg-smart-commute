import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Flutter's own focus highlight mode, for the widgets that draw a focus
/// ring (E7 D1; no custom input tracker). In Flutter 3.47.2 a hardware key
/// event makes it traditional and a touch or stylus pointer makes it touch;
/// a mouse or trackpad leaves it as it is, and so does an Android
/// soft-keyboard key event. Before the first touch or key the mode is the
/// platform default: traditional on desktop, and on a phone touch unless a
/// mouse is connected. That default changes without telling highlight-mode
/// listeners, so the scope also re-reads the mode when a mouse connects or
/// disconnects. Installed once, in `MaterialApp.builder`; a mode change
/// rebuilds only the widgets that read it.
class FocusHighlightScope extends StatefulWidget {
  const FocusHighlightScope({super.key, required this.child});

  final Widget child;

  /// Whether a focused control under [context] should show its ring: true in
  /// traditional mode. Without a scope above, it reads `FocusManager`
  /// directly and does not rebuild on a change.
  static bool showsFocusOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_HighlightMode>()
          ?.traditional ??
      _traditionalNow();

  @override
  State<FocusHighlightScope> createState() => _FocusHighlightScopeState();
}

bool _traditionalNow() =>
    FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

class _FocusHighlightScopeState extends State<FocusHighlightScope> {
  bool _traditional = _traditionalNow();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_changed);
    RendererBinding.instance.mouseTracker.addListener(_resample);
  }

  @override
  void dispose() {
    RendererBinding.instance.mouseTracker.removeListener(_resample);
    FocusManager.instance.removeHighlightModeListener(_changed);
    super.dispose();
  }

  void _changed(FocusHighlightMode _) => _resample();

  /// Re-reads the mode: also the platform default, which follows whether a
  /// mouse is connected.
  void _resample() {
    final traditional = _traditionalNow();
    if (traditional != _traditional) {
      setState(() => _traditional = traditional);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _HighlightMode(traditional: _traditional, child: widget.child);
}

class _HighlightMode extends InheritedWidget {
  const _HighlightMode({required this.traditional, required super.child});

  final bool traditional;

  @override
  bool updateShouldNotify(_HighlightMode oldWidget) =>
      oldWidget.traditional != traditional;
}
