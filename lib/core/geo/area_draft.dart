import '../models/geo_point.dart';
import 'polygon.dart';

/// Editable play-area polygon with undo (R-SET-06). Immutable; every edit
/// returns a new draft.
class AreaDraft {
  const AreaDraft(this.points, [this._history = const []]);

  final List<GeoPoint> points;
  final List<List<GeoPoint>> _history;

  bool get canUndo => _history.isNotEmpty;
  bool get hasMinimumPoints => points.length >= 3;
  bool get isSimple => isSimplePolygon(points);

  /// Can be saved as play area.
  bool get isValid => hasMinimumPoints && isSimple;

  double get areaKm2 => polygonAreaKm2(points);

  AreaDraft _edit(List<GeoPoint> next) => AreaDraft(
    List.unmodifiable(next),
    List.unmodifiable([..._history, points]),
  );

  /// Appends a corner (tap on the map).
  AreaDraft add(GeoPoint p) => _edit([...points, p]);

  /// Inserts a corner on the edge after [index] (tap on a "+" handle).
  AreaDraft insertAfter(int index, GeoPoint p) =>
      _edit([...points]..insert(index + 1, p));

  /// Moves a corner. During a drag, pass [record] = false for intermediate
  /// positions so one drag is one undo step (call [beginMove] first).
  AreaDraft move(int index, GeoPoint p, {bool record = true}) {
    final next = [...points]..[index] = p;
    return record ? _edit(next) : AreaDraft(List.unmodifiable(next), _history);
  }

  /// Records the state before a drag so it can be undone in one step.
  AreaDraft beginMove() => _edit(points);

  AreaDraft remove(int index) => _edit([...points]..removeAt(index));

  AreaDraft clear() => points.isEmpty ? this : _edit(const []);

  AreaDraft undo() => canUndo
      ? AreaDraft(_history.last, _history.sublist(0, _history.length - 1))
      : this;

  /// Midpoint of the edge from corner [index] to the next one.
  GeoPoint midpoint(int index) {
    final a = points[index];
    final b = points[(index + 1) % points.length];
    return GeoPoint((a.lat + b.lat) / 2, (a.lng + b.lng) / 2);
  }
}
