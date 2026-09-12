// A closure or local function is its own scope. Its body is one level
// deeper than the point where it is written, so a closure's own score says
// how hard it is to read where it sits, and `include_in_parent` adds the
// children's scores to the parent: the whole-method number.

// expect: cognitive=0 rolled=2
void forEachIf(List<int> xs) {
  // expect: cognitive=2
  xs.forEach((x) {
    if (x > 0) print(x); // +2: one level for the closure
  });
}

// A closure inside an `if` body starts two levels deep.
// expect: cognitive=1 rolled=4
void inIf(List<int> xs) {
  if (xs.isNotEmpty) {
    // expect: cognitive=3
    xs.forEach((x) {
      if (x > 0) print(x);
    });
  }
}

// A closure with no constructs is 0 wherever it sits.
// expect: cognitive=0 rolled=0
void plain(List<int> xs) {
  // expect: cognitive=0
  xs.map((x) => x + 1);
}

// A boolean run inside a closure pays nothing for the closure's level.
// expect: cognitive=0 rolled=1
void runInClosure(List<int> xs) {
  // expect: cognitive=1
  xs.where((x) => x > 0 && x < 10);
}

// A closure in a closure: the inner `if` is three levels deep.
// expect: cognitive=0 rolled=3
void nestedClosures(List<List<int>> rows) {
  // expect: cognitive=0 rolled=3
  rows.forEach((row) {
    // expect: cognitive=3
    row.forEach((x) {
      if (x > 0) print(x);
    });
  });
}

// A local function is a closure with a name.
// expect: cognitive=0 rolled=2
void withLocal() {
  // expect: cognitive=2
  int helper(int v) {
    if (v > 0) return v;
    return 0;
  }

  helper(1);
}

// Closures in initializers have no enclosing body: level 0, like a function.
// expect: cognitive=1
final topLevelHandler = (int a) => a > 0 ? a : -a;

class C {
  // expect: cognitive=1
  final compare = (int a, int b) => a > b ? a : b;
}
