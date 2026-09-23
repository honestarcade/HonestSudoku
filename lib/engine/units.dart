// Peers and named units, precomputed once per shape.
//
// The order and names are the design's `unitList`: every row, then every
// column, then every box row-major, named `row k`, `column k` and `this box`.
// The hint engine walks units in this order, so the unit a hint names is the
// one the prototype would have named.

import 'grid.dart';
import 'list_equality.dart';

/// The three kinds of unit.
enum UnitKind { row, column, box }

/// One row, column or box.
final class Unit {
  /// Creates a unit. [cells] should be unmodifiable and ascending.
  const Unit({
    required this.kind,
    required this.ordinal,
    required this.name,
    required this.cells,
  });

  /// Row, column or box.
  final UnitKind kind;

  /// 1-based position within its kind.
  final int ordinal;

  /// The design's name: `row k`, `column k` or `this box`.
  final String name;

  /// The unit's cell indices, ascending.
  final List<int> cells;

  @override
  bool operator ==(Object other) =>
      other is Unit &&
      other.kind == kind &&
      other.ordinal == ordinal &&
      other.name == name &&
      listEquals(other.cells, cells);

  @override
  int get hashCode => Object.hash(kind, ordinal, name, Object.hashAll(cells));

  @override
  String toString() =>
      kind == UnitKind.box ? 'Unit(box $ordinal)' : 'Unit($name)';
}

/// Precomputed tables for one shape.
final class UnitTables {
  UnitTables._(this.peers, this.units, this.unitsOfCell);

  /// `peers[i]`: every cell sharing a row, column or box with `i`, ascending,
  /// excluding `i`.
  final List<List<int>> peers;

  /// Every unit in the design's order.
  final List<Unit> units;

  /// `unitsOfCell[i]`: indices into [units] of the row, column and box of `i`.
  final List<List<int>> unitsOfCell;

  static final Map<GridShape, UnitTables> _cache = {};

  /// The tables for [shape], built on first use.
  static UnitTables of(GridShape shape) =>
      _cache.putIfAbsent(shape, () => _build(shape));

  static UnitTables _build(GridShape shape) {
    final n = shape.n;
    final units = <Unit>[];
    for (var r = 0; r < n; r++) {
      units.add(
        Unit(
          kind: UnitKind.row,
          ordinal: r + 1,
          name: 'row ${r + 1}',
          cells: List.unmodifiable([for (var c = 0; c < n; c++) r * n + c]),
        ),
      );
    }
    for (var c = 0; c < n; c++) {
      units.add(
        Unit(
          kind: UnitKind.column,
          ordinal: c + 1,
          name: 'column ${c + 1}',
          cells: List.unmodifiable([for (var r = 0; r < n; r++) r * n + c]),
        ),
      );
    }
    var box = 0;
    for (var br = 0; br < n; br += shape.boxH) {
      for (var bc = 0; bc < n; bc += shape.boxW) {
        box++;
        units.add(
          Unit(
            kind: UnitKind.box,
            ordinal: box,
            name: 'this box',
            cells: List.unmodifiable([
              for (var r = br; r < br + shape.boxH; r++)
                for (var c = bc; c < bc + shape.boxW; c++) r * n + c,
            ]),
          ),
        );
      }
    }

    final unitsOfCell = List.generate(shape.cellCount, (_) => <int>[]);
    for (var u = 0; u < units.length; u++) {
      for (final cell in units[u].cells) {
        unitsOfCell[cell].add(u);
      }
    }

    final peers = List<List<int>>.generate(shape.cellCount, (i) {
      final set = <int>{};
      for (final u in unitsOfCell[i]) {
        set.addAll(units[u].cells);
      }
      set.remove(i);
      return List.unmodifiable(set.toList()..sort());
    });

    return UnitTables._(
      List.unmodifiable(peers),
      List.unmodifiable(units),
      List.unmodifiable([
        for (final l in unitsOfCell) List<int>.unmodifiable(l),
      ]),
    );
  }
}

/// The row, column and box peers of [index], ascending, excluding [index].
List<int> unitsOf(GridShape shape, int index) {
  checkIndex(shape, index);
  return UnitTables.of(shape).peers[index];
}

/// Every unit of [shape] in the design's order: rows, columns, then boxes.
List<Unit> unitList(GridShape shape) => UnitTables.of(shape).units;
