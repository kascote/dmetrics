// Fixture for the M0 dummy metric `ifcount`: 1 + number of `if` statements.

// expect: ifcount=3
int topLevel(int a) {
  if (a > 0) {
    if (a > 10) return 2;
  }
  return 0;
}

// expect: ifcount=1
int noBranches() => 42;

class C {
  final int x;

  // expect: ifcount=2
  C(this.x) {
    if (x < 0) throw ArgumentError('x');
  }

  // expect: ifcount=2
  C.named(this.x) : assert(x >= 0) {
    if (x == 0) print('zero');
  }

  // expect: ifcount=3
  int get sign {
    if (x > 0) return 1;
    if (x < 0) return -1;
    return 0;
  }

  // expect: ifcount=2
  set value(int v) {
    if (v != x) print(v);
  }

  // expect: ifcount=2
  bool operator ==(Object other) {
    if (other is! C) return false;
    return other.x == x;
  }

  // Metadata is part of the scope span, so the annotation precedes it.
  // expect: ifcount=1
  @override
  int get hashCode => x;

  // expect: ifcount=3
  void withLocal(List<int> xs) {
    // expect: ifcount=2
    int helper(int v) {
      if (v > 1) return v;
      return 0;
    }

    if (xs.isEmpty) return;
    if (helper(xs.first) > 0) print('x');
  }

  // expect: ifcount=2
  void withClosure(List<int> xs) {
    if (xs.isEmpty) return;
    // expect: ifcount=2
    xs.forEach((v) {
      if (v > 0) print(v);
    });
  }
}

abstract class A {
  // expect: none
  void abstractMethod();

  // expect: none
  external void externalMethod();
}
