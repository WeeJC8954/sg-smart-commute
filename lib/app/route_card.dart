import 'package:flutter/material.dart';

import '../core/ui/motion.dart';
import '../features/destination/presentation/destination_card.dart';
import '../features/origin/presentation/origin_card.dart';

/// Where the trip starts and ends, as one card (guide v2.1 §16 "From: …",
/// then "Where are you heading today?"). The origin and destination keep
/// their own controllers; this only groups them. Search results, "Change"
/// and the destination's arrival all resize the card, so it animates.
class RouteCard extends StatelessWidget {
  const RouteCard({super.key});

  @override
  Widget build(BuildContext context) => const MotionSize(
    child: Card(
      key: Key('route-card'),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [OriginCard(), DestinationCard()],
        ),
      ),
    ),
  );
}
