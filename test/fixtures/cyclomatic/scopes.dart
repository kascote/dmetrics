// Every measured scope kind starts at 1.
class C {
  final int x;

  // A constructor with a `;` body but an initializer list is still measured;
  // initializer-list branches belong to it.
  // expect: cyclomatic=2
  C(int a) : x = a > 0 ? a : 0;

  // expect: cyclomatic=1
  const C.zero() : x = 0;

  // expect: cyclomatic=2
  int get sign => x > 0 ? 1 : 0;

  // expect: cyclomatic=2
  set value(int v) {
    if (v < 0) throw ArgumentError('v');
  }

  // expect: cyclomatic=2
  bool operator ==(Object other) => other is C && other.x == x;

  // A local function is its own scope.
  // expect: cyclomatic=1
  void outer() {
    // expect: cyclomatic=2
    int helper(int v) => v > 0 ? v : 0;
    helper(x);
  }

  // Branch constructs directly in field initializers (outside any closure)
  // are delivered with the class context and ignored in v1 (§6.1).
  final int initialized = 1 > 0 ? 1 : 2;
}

abstract class A {
  // expect: none
  void abstractMethod();

  // expect: none
  external void externalMethod();

  // expect: none
  factory A.make() = B;
}

class B implements A {
  // expect: cyclomatic=1
  @override
  void abstractMethod() {}

  // expect: cyclomatic=1
  @override
  void externalMethod() {}
}
