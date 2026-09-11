class C {
  // A field-initializer closure lives under the class context: its `if`
  // must not land anywhere else, and the class itself is never measured.
  // expect: nesting=1
  final f = () {
    if (true) {}
  };

  // A local function inside a constructor is its own scope.
  // expect: nesting=1 rolled=3
  C() {
    // expect: nesting=3
    void helper(int a) {
      if (a > 0) {
        try {
          if (a > 1) {}
        } catch (_) {}
      }
    }

    if (f != null) helper(1);
  }

  // Deeper code after the closure than before it, inside one scope.
  // expect: nesting=3
  void deep(int a) {
    if (a > 0) {
      // expect: nesting=0
      final g = () => a;
      switch (a) {
        case 1:
          if (g() > 0) {}
      }
    }
  }
}
