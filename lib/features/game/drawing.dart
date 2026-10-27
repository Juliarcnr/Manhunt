import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/drawing/stroke.dart';
import '../../core/drawing/stroke_geometry.dart';
import '../../core/models/geo_point.dart';
import '../../data/game_repository.dart';
import '../../data/round_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../map/base_map.dart';

/// In drawing mode one finger draws, two fingers zoom and pan (R-DRAW-02).
const drawingInteraction = InteractionOptions(
  flags: InteractiveFlag.pinchZoom | InteractiveFlag.pinchMove,
);

/// Fixed line width in logical pixels (R-DRAW-03).
const strokeWidthPx = 5.0;

/// Radius of the eraser around the finger, in logical pixels (R-DRAW-04).
const eraserRadiusPx = 16.0;

/// Points closer than this to the previous one are dropped.
const _minPointDistancePx = 2.0;

/// Points per stored stroke document; longer strokes are split.
const _maxPointsPerStroke = 400;

Color strokeColorOf(StrokeColor color) => switch (color) {
  StrokeColor.red => AppColors.drawRed,
  StrokeColor.blue => AppColors.drawBlue,
  StrokeColor.green => AppColors.drawGreen,
  StrokeColor.black => AppColors.drawBlack,
};

/// The hunters' drawing mode (R-DRAW-01…06): pen, colour, eraser and the
/// strokes saved by this device but not yet echoed by Firestore.
class DrawingController extends ChangeNotifier {
  DrawingController({
    required this.session,
    required this.rounds,
    required this.server,
    this.onError,
    Random? random,
  }) : _random = random ?? Random();

  final GroupSession session;
  final RoundRepository rounds;

  /// The strokes as currently stored (from the drawings stream).
  final List<Stroke> Function() server;
  void Function(Object error)? onError;
  final Random _random;

  var _active = false;
  var _color = StrokeColor.red;
  var _erasing = false;

  bool get active => _active;
  StrokeColor get color => _color;
  bool get erasing => _erasing;

  /// Saved by this device, shown until the stream contains them.
  final _pending = <String, Stroke>{};

  /// Erased or cleared by this device, hidden until gone from the stream.
  final _hidden = <String>{};

  /// Pen: the line being drawn. Eraser: the path of the finger.
  List<GeoPoint>? _path;
  var _metresPerPx = 1.0;

  /// Eraser: remaining pieces of the strokes touched so far, by stroke id.
  final _erased = <String, List<List<GeoPoint>>>{};

  void toggle() {
    _active = !_active;
    _erasing = false;
    cancel();
    notifyListeners();
  }

  void pickColor(StrokeColor color) {
    _color = color;
    _erasing = false;
    notifyListeners();
  }

  void toggleEraser() {
    _erasing = !_erasing;
    notifyListeners();
  }

  /// Stored and own unsaved strokes, minus what this device erased.
  List<Stroke> _base(List<Stroke> server) {
    final ids = {for (final s in server) s.id};
    return [
      for (final s in server)
        if (!_hidden.contains(s.id)) s,
      for (final s in _pending.values)
        if (!ids.contains(s.id) && !_hidden.contains(s.id)) s,
    ];
  }

  /// What the map shows: [server] with this device's changes applied,
  /// including the stroke being drawn or erased right now.
  List<Stroke> visible(List<Stroke> server) => [
    for (final s in _base(server))
      if (_erased[s.id] case final pieces?)
        for (final piece in pieces) _copy(s, piece)
      else
        s,
    if (_path case final path? when !_erasing && path.isNotEmpty)
      Stroke(
        id: '',
        uid: session.userId,
        color: _color,
        points: path.length == 1 ? [path.first, path.first] : path,
      ),
  ];

  /// Forgets local changes once the stream reflects them.
  void prune(List<Stroke> server) {
    final ids = {for (final s in server) s.id};
    _pending.removeWhere((id, _) => ids.contains(id));
    _hidden.removeWhere((id) => !ids.contains(id) && !_pending.containsKey(id));
  }

  /// A single finger touches the map; [metresPerPx] at the current zoom.
  void begin(GeoPoint point, double metresPerPx) {
    _metresPerPx = metresPerPx;
    _path = [point];
    _erased.clear();
    if (_erasing) _erase([point]);
    notifyListeners();
  }

  void extend(GeoPoint point) {
    final path = _path;
    if (path == null) return;
    if (_erasing) _erase([path.last, point]);
    path.add(point);
    notifyListeners();
  }

  /// A second finger: this is a pinch, not a line (R-DRAW-02).
  void cancel() {
    _path = null;
    _erased.clear();
    notifyListeners();
  }

  /// The finger is lifted: save the line or the erasure (R-DRAW-06).
  void end() {
    final path = _path;
    _path = null;
    if (path == null) return;
    if (_erasing) {
      _commitErasure();
    } else {
      _commitLine(path);
    }
    notifyListeners();
  }

  void _erase(List<GeoPoint> segment) {
    final radiusM = eraserRadiusPx * _metresPerPx;
    for (final s in _base(server())) {
      final pieces = _erased[s.id] ?? [s.points];
      var touched = false;
      final next = <List<GeoPoint>>[];
      for (final piece in pieces) {
        final rest = eraseFromStroke(piece, segment, radiusM);
        if (rest == null) {
          next.add(piece);
        } else {
          touched = true;
          next.addAll(rest);
        }
      }
      if (touched) _erased[s.id] = next;
    }
  }

  void _commitLine(List<GeoPoint> path) {
    var points = simplifyStroke(path, _minPointDistancePx * _metresPerPx);
    // A tap leaves a dot.
    if (points.length == 1) points = [points.first, points.first];
    final strokes = [
      for (final piece in splitLongStroke(points, _maxPointsPerStroke))
        Stroke(id: _newId(), uid: session.userId, color: _color, points: piece),
    ];
    _save(removeIds: const [], add: strokes);
  }

  void _commitErasure() {
    if (_erased.isEmpty) return;
    final byId = {for (final s in _base(server())) s.id: s};
    final removeIds = _erased.keys.toList();
    final add = [
      for (final MapEntry(key: id, value: pieces) in _erased.entries)
        if (byId[id] case final original?)
          for (final piece in pieces) _copy(original, piece, id: _newId()),
    ];
    _erased.clear();
    _save(removeIds: removeIds, add: add);
  }

  /// Trash can (R-DRAW-04): deletes all strokes of all hunters.
  void clear() {
    _hidden.addAll(_base(server()).map((s) => s.id));
    _pending.clear();
    notifyListeners();
    unawaited(_run(() => rounds.clearDrawings(session), const []));
  }

  void _save({required List<String> removeIds, required List<Stroke> add}) {
    _hidden.addAll(removeIds);
    for (final s in add) {
      _pending[s.id] = s;
    }
    unawaited(
      _run(
        () => rounds.replaceStrokes(session, removeIds: removeIds, add: add),
        [...removeIds, ...add.map((s) => s.id)],
      ),
    );
  }

  /// Runs a write; on failure the local changes are dropped again.
  Future<void> _run(Future<void> Function() write, List<String> ids) async {
    try {
      await write();
    } on Object catch (e) {
      if (ids.isEmpty) _hidden.clear();
      for (final id in ids) {
        _pending.remove(id);
        _hidden.remove(id);
      }
      notifyListeners();
      onError?.call(e);
    }
  }

  Stroke _copy(Stroke s, List<GeoPoint> points, {String id = ''}) =>
      Stroke(id: id, uid: s.uid, color: s.color, points: points);

  static const _idChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  String _newId() => String.fromCharCodes([
    for (var i = 0; i < 20; i++)
      _idChars.codeUnitAt(_random.nextInt(_idChars.length)),
  ]);
}

/// Turns single-finger touches on the map into pen or eraser strokes while
/// the drawing mode is on. A [Listener] doesn't take part in the gesture
/// arena, so the map still gets two-finger zoom and pan (R-DRAW-02).
class DrawingGestures extends StatefulWidget {
  const DrawingGestures({
    super.key,
    required this.controller,
    required this.map,
    required this.enabled,
    required this.child,
  });

  final DrawingController controller;
  final MapController map;
  final bool enabled;
  final Widget child;

  @override
  State<DrawingGestures> createState() => _DrawingGesturesState();
}

class _DrawingGesturesState extends State<DrawingGestures> {
  final _pointers = <int>{};

  /// Set once a second finger touched; cleared when all fingers are up.
  var _pinching = false;

  GeoPoint _toGeo(Offset local) =>
      widget.map.camera.screenOffsetToLatLng(local).toGeoPoint();

  double _metresPerPx(Offset local) {
    const span = 100.0;
    final a = _toGeo(local);
    final b = _toGeo(local + const Offset(span, 0));
    return geoDistanceM(a, b) / span;
  }

  void _down(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (!widget.enabled) return;
    if (_pointers.length == 1) {
      widget.controller.begin(
        _toGeo(e.localPosition),
        _metresPerPx(e.localPosition),
      );
    } else if (!_pinching) {
      _pinching = true;
      widget.controller.cancel();
    }
  }

  void _move(PointerMoveEvent e) {
    if (!widget.enabled || _pinching || _pointers.length != 1) return;
    widget.controller.extend(_toGeo(e.localPosition));
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (widget.enabled && !_pinching && _pointers.isEmpty) {
      if (e is PointerCancelEvent) {
        widget.controller.cancel();
      } else {
        widget.controller.end();
      }
    }
    if (_pointers.isEmpty) _pinching = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.child,
  );
}

/// Pen colours, eraser and trash can, shown while drawing (R-DRAW-03,
/// R-DRAW-04).
class DrawingToolbar extends StatelessWidget {
  const DrawingToolbar({
    super.key,
    required this.controller,
    required this.onClear,
  });

  final DrawingController controller;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        elevation: 4,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in StrokeColor.values)
                _ColorDot(
                  key: Key('drawColor_${c.name}'),
                  color: strokeColorOf(c),
                  tooltip: switch (c) {
                    StrokeColor.red => l10n.drawColorRed,
                    StrokeColor.blue => l10n.drawColorBlue,
                    StrokeColor.green => l10n.drawColorGreen,
                    StrokeColor.black => l10n.drawColorBlack,
                  },
                  selected: !controller.erasing && controller.color == c,
                  onTap: () => controller.pickColor(c),
                ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('drawEraserButton'),
                tooltip: l10n.drawEraser,
                isSelected: controller.erasing,
                style: IconButton.styleFrom(
                  backgroundColor: controller.erasing
                      ? AppColors.surfaceHigh
                      : null,
                ),
                onPressed: controller.toggleEraser,
                icon: const Icon(Icons.auto_fix_normal),
              ),
              IconButton(
                key: const Key('drawClearButton'),
                tooltip: l10n.drawClear,
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    super.key,
    required this.color,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : AppColors.outline,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Hunters' drawings (R-DRAW-05): shown whether or not the mode is on.
Widget drawingsLayer(List<Stroke> strokes) => PolylineLayer(
  polylines: [
    for (final s in strokes)
      Polyline(
        points: [for (final p in s.points) p.toLatLng()],
        color: strokeColorOf(s.color),
        strokeWidth: strokeWidthPx,
      ),
  ],
);
