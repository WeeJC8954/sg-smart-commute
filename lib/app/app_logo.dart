import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app.dart';

/// The app-bar title: the mark, then the app name. On a narrow screen the
/// name is shortened with an ellipsis; the mark keeps its size.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppLogo(key: Key('app-logo')),
      SizedBox(width: 10),
      Flexible(
        child: Text(SmartCommuteApp.title, overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// The app's mark: a rounded tile with a route curving from a start point to
/// a destination pin. Painted in code (no image asset), so it is sharp at any
/// size and follows the theme: the tile is `primary`, the route `onPrimary`.
///
/// Decorative: it always sits next to the app title, so screen readers skip it.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: AppLogoPainter(tile: scheme.primary, mark: scheme.onPrimary),
      ),
    );
  }
}

/// Paints [AppLogo] in a unit square scaled to the canvas size.
class AppLogoPainter extends CustomPainter {
  const AppLogoPainter({required this.tile, required this.mark});

  final Color tile;
  final Color mark;

  // Geometry in unit coordinates (0–1, y down).
  static const Offset _start = Offset(0.25, 0.76);
  static const double _startRadius = 0.085;
  static const Offset _pinCentre = Offset(0.69, 0.35);
  static const double _pinRadius = 0.165;
  static const Offset _pinTip = Offset(0.69, 0.76);
  static const double _pinHoleRadius = 0.065;
  static const double _routeWidth = 0.07;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & const Size(1, 1),
        const Radius.circular(0.24),
      ),
      Paint()..color = tile,
    );

    final markPaint = Paint()
      ..color = mark
      ..isAntiAlias = true;

    // The route: from the start point over a smooth hump, arriving at the
    // pin's tip horizontally, so it never cuts into the pin's body.
    final route = Path()
      ..moveTo(_start.dx, _start.dy)
      ..cubicTo(0.30, 0.50, 0.47, 0.50, 0.54, 0.68)
      ..quadraticBezierTo(0.575, 0.76, _pinTip.dx, _pinTip.dy);
    canvas.drawPath(
      route,
      Paint()
        ..color = mark
        ..style = PaintingStyle.stroke
        ..strokeWidth = _routeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(_start, _startRadius, markPaint);

    canvas
      ..drawPath(_pin(), markPaint)
      ..drawCircle(_pinCentre, _pinHoleRadius, Paint()..color = tile);

    canvas.restore();
  }

  /// A teardrop pin: the head circle plus the two tangents down to the tip.
  static Path _pin() {
    final toTip = _pinTip - _pinCentre;
    final pointingAngle = math.atan2(toTip.dy, toTip.dx);
    final spread = math.acos(_pinRadius / toTip.distance);
    final head = Rect.fromCircle(center: _pinCentre, radius: _pinRadius);
    return Path()
      ..moveTo(_pinTip.dx, _pinTip.dy)
      ..arcTo(head, pointingAngle + spread, 2 * math.pi - 2 * spread, false)
      ..close();
  }

  @override
  bool shouldRepaint(AppLogoPainter oldDelegate) =>
      oldDelegate.tile != tile || oldDelegate.mark != mark;
}
