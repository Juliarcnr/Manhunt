import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Like [MarkerLayer], but a marker whose point changes glides to its new
/// position instead of jumping – like the live location in messenger apps
/// (R-MAP-04). Markers are matched by their key; a marker without a key, or
/// one shown for the first time, appears right away.
class AnimatedMarkerLayer extends StatefulWidget {
  const AnimatedMarkerLayer({
    super.key,
    required this.markers,
    this.duration = const Duration(seconds: 1),
    this.curve = Curves.linear,
  });

  final List<Marker> markers;

  /// How long a marker takes to its new position. For a position stream
  /// about the update interval, so the marker moves continuously.
  final Duration duration;
  final Curve curve;

  @override
  State<AnimatedMarkerLayer> createState() => _AnimatedMarkerLayerState();
}

class _AnimatedMarkerLayerState extends State<AnimatedMarkerLayer>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );

  /// Where each marker started its current move (missing = no move).
  var _from = <Key, LatLng>{};
  late var _to = _targets(widget.markers);

  static Map<Key, LatLng> _targets(List<Marker> markers) => {
    for (final m in markers) ?m.key: m.point,
  };

  LatLng _current(Key key) {
    final to = _to[key]!;
    final from = _from[key];
    if (from == null) return to;
    final t = _progress.value;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }

  @override
  void didUpdateWidget(AnimatedMarkerLayer old) {
    super.didUpdateWidget(old);
    _controller.duration = widget.duration;
    final targets = _targets(widget.markers);
    if (mapEquals(targets, _to)) return;
    // Continue from where the markers are right now, not from their last
    // target – a new position may arrive mid-move.
    _from = {
      for (final key in targets.keys)
        if (_to.containsKey(key)) key: _current(key),
    };
    _to = targets;
    unawaited(_controller.forward(from: 0));
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _progress,
    builder: (context, _) => MarkerLayer(
      markers: [
        for (final m in widget.markers)
          if (m.key case final key?)
            Marker(
              key: key,
              point: _current(key),
              width: m.width,
              height: m.height,
              alignment: m.alignment,
              rotate: m.rotate,
              child: m.child,
            )
          else
            m,
      ],
    ),
  );
}
