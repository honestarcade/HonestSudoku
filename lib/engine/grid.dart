// Grid shapes, symbols and cell naming.
//
// The four shapes are the design's SIZES table. The set is closed: every
// engine function takes one of these instances, so nothing downstream has to
// cope with a shape the design never draws.

/// The design's `SYM` string: values 1–9, then A–G for 10–16.
const String kSymbols = '123456789ABCDEFG';

/// One of the four supported grid shapes.
final class GridShape {
  const GridShape._({
    required this.n,
    required this.boxH,
    required this.boxW,
    required this.label,
    required this.sub,
  });

  /// 4×4 with 2×2 boxes.
  static const mini = GridShape._(
    n: 4,
    boxH: 2,
    boxW: 2,
    label: '4×4',
    sub: 'MINI',
  );

  /// 6×6 with boxes 2 rows high and 3 columns wide.
  static const short = GridShape._(
    n: 6,
    boxH: 2,
    boxW: 3,
    label: '6×6',
    sub: 'SHORT',
  );

  /// 9×9 with 3×3 boxes.
  static const classic = GridShape._(
    n: 9,
    boxH: 3,
    boxW: 3,
    label: '9×9',
    sub: 'CLASSIC',
  );

  /// 16×16 with 4×4 boxes, symbols 1–9 then A–G.
  static const monster = GridShape._(
    n: 16,
    boxH: 4,
    boxW: 4,
    label: '16×16',
    sub: 'MONSTER',
  );

  /// Every shape, in the design's order.
  static const List<GridShape> all = [mini, short, classic, monster];

  /// Side length: the number of values, rows and columns.
  final int n;

  /// Box height in rows.
  final int boxH;

  /// Box width in columns.
  final int boxW;

  /// The design's label, e.g. `9×9`.
  final String label;

  /// The design's subtitle, e.g. `CLASSIC`.
  final String sub;

  /// Cells in the grid, `n²`.
  int get cellCount => n * n;

  /// Looks a shape up by its label; accepts `9×9` and `9x9`.
  static GridShape byLabel(String label) {
    final normalised = label.replaceAll('x', '×');
    for (final shape in all) {
      if (shape.label == normalised) return shape;
    }
    throw ArgumentError.value(label, 'label', 'not a supported grid shape');
  }

  /// Zero-based row of [index].
  int rowOf(int index) => index ~/ n;

  /// Zero-based column of [index].
  int colOf(int index) => index % n;

  /// Zero-based box ordinal of [index], boxes numbered row-major.
  int boxOf(int index) {
    final boxesPerRow = n ~/ boxW;
    return (rowOf(index) ~/ boxH) * boxesPerRow + colOf(index) ~/ boxW;
  }

  /// The symbol for [value]: `''` for 0 (empty), else `kSymbols[value - 1]`.
  String symbolFor(int value) {
    if (value == 0) return '';
    if (value < 0 || value > n) {
      throw ArgumentError.value(value, 'value', 'outside 0..$n for $label');
    }
    return kSymbols[value - 1];
  }

  @override
  String toString() => 'GridShape($label)';
}

/// `R<r>C<c>` for [index], both 1-based, as the design names cells.
String cellName(GridShape shape, int index) {
  checkIndex(shape, index);
  return 'R${shape.rowOf(index) + 1}C${shape.colOf(index) + 1}';
}

/// Throws when [index] is not a cell of [shape].
void checkIndex(GridShape shape, int index) {
  if (index < 0 || index >= shape.cellCount) {
    throw RangeError.range(index, 0, shape.cellCount - 1, 'index');
  }
}

/// Throws when [values] is not a grid of [shape]: wrong length, or an entry
/// outside `0..n`.
void checkValues(GridShape shape, List<int> values, [String name = 'values']) {
  if (values.length != shape.cellCount) {
    throw ArgumentError.value(
      values.length,
      name,
      'length must be ${shape.cellCount} for ${shape.label}',
    );
  }
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (v < 0 || v > shape.n) {
      throw ArgumentError.value(v, '$name[$i]', 'outside 0..${shape.n}');
    }
  }
}
