// Every measured scope kind starts at 0.
class C {
  final int x;

  // A constructor with a `;` body but an initializer list is still measured;
  // initializer-list branches belong to it.
  // expect: cognitive=1
  C(int a) : x = a > 0 ? a : 0;

  // expect: cognitive=0
  const C.zero() : x = 0;

  // expect: cognitive=1
  int get sign => x > 0 ? 1 : 0;

  // expect: cognitive=1
  set value(int v) {
    if (v < 0) throw ArgumentError('v');
  }

  // expect: cognitive=1
  bool operator ==(Object other) => other is C && other.x == x;

  // expect: cognitive=0
  @override
  int get hashCode => x;

  // Branch constructs directly in field initializers (outside any closure)
  // are delivered with the class context and ignored, as cyclomatic does.
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
  // expect: cognitive=0
  @override
  void abstractMethod() {}

  // expect: cognitive=0
  @override
  void externalMethod() {}
}
