// A closure is its own scope; it never contributes to the parent's measured
// value. Under include_in_parent the parent's value folds it in (§6.3).
// expect: cyclomatic=2 rolled=4
void parent(List<int> xs) {
  if (xs.isEmpty) return;
  // expect: cyclomatic=3
  xs.where((x) {
    if (x > 0) return true;
    return x < -10 && x.isEven;
  });
}

// Closures in top-level and field initializers are measured under the
// structural context.
// expect: cyclomatic=2
final topLevelHandler = (int a) => a > 0 ? a : -a;

class C {
  // expect: cyclomatic=2
  final compare = (int a, int b) => a > b || a == b;
}
