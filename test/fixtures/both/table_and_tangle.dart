// Two real metrics on one traversal. The shapes cyclomatic misreads as
// tangles (tables, boilerplate) score low in cognitive; a real tangle
// scores higher in cognitive than in cyclomatic.

// A dispatch table: cyclomatic counts every arm, cognitive counts the switch.
// expect: cyclomatic=6 cognitive=1
String table(int n) => switch (n) {
  1 => 'one',
  2 => 'two',
  3 => 'three',
  4 => 'four',
  5 => 'five',
  _ => 'many',
};

// Field-wise boilerplate: cyclomatic counts each `??`, cognitive nothing.
class Point {
  final int x;
  final int y;
  final int z;

  // expect: cyclomatic=1 cognitive=0
  const Point(this.x, this.y, this.z);

  // expect: cyclomatic=4 cognitive=0
  Point copyWith({int? x, int? y, int? z}) =>
      Point(x ?? this.x, y ?? this.y, z ?? this.z);

  // expect: cyclomatic=4 cognitive=1
  @override
  bool operator ==(Object other) =>
      other is Point && other.x == x && other.y == y && other.z == z;

  // expect: cyclomatic=1 cognitive=0
  @override
  int get hashCode => Object.hash(x, y, z);
}

// A tangle: three nested `if`s with an `else`.
// expect: cyclomatic=4 cognitive=7
int tangle(int a, int b, int c) {
  if (a > 0) {
    if (b > 0) {
      if (c > 0) return 1;
    } else {
      return 2;
    }
  }
  return 0;
}

// Both metrics roll closures up, each by its own rule.
// expect: cyclomatic=2 rolled=3 cognitive=1 rolled=3
void rolled(List<int> xs) {
  if (xs.isEmpty) return;
  // expect: cyclomatic=2 cognitive=2
  xs.forEach((x) {
    if (x > 0) print(x);
  });
}
