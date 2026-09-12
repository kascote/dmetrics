// Null-aware shorthand is 0: `??`, `??=`, `?.`, `?..`, `?[]`, `!`, `...?`
// and the null-aware element `?x`. Each collapses a null check the reader
// would otherwise follow as statements; cyclomatic counts `??` and `?x`.

// expect: cognitive=0
int coalesce(int? a, int? b) {
  var x = a ?? 0;
  x ??= b ?? 1;
  return x;
}

// expect: cognitive=0
int? chain(String? s) => s?.trim().length;

// expect: cognitive=0
List<int> elements(int? a, List<int>? xs, Map<int, int>? m) => [
  ?a,
  ...?xs,
  xs?.length ?? 0,
  xs![0],
  ?m?[1],
];

// expect: cognitive=0
Map<int, int> mapEntries(int? k, int? v) => {?k: 1, 2: ?v};

// expect: cognitive=0
StringBuffer? cascade(StringBuffer? sb) => sb?..write('x');

// A `copyWith` scores 0 here and its field count in cyclomatic.
class Point {
  final int x;
  final int y;
  final int z;

  // expect: cognitive=0
  const Point(this.x, this.y, this.z);

  // expect: cognitive=0
  Point copyWith({int? x, int? y, int? z}) =>
      Point(x ?? this.x, y ?? this.y, z ?? this.z);
}
