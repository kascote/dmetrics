// Three-level roll-up (SPEC §6.3): 2 / 3 / 4 under include_in_parent.
// Each child's base score is excluded: 2 + (3 - 1) = 4, 2 + (2 - 1) = 3.

// expect: ifcount=2 rolled=4
void outer(List<int> xs) {
  if (xs.isEmpty) return;
  // expect: ifcount=2 rolled=3
  xs.forEach((x) {
    if (x > 0) return;
    // expect: ifcount=2
    [x].forEach((y) {
      if (y > 1) print(y);
    });
  });
}

// A method of 2 with two direct closures of 3 and 2 reports 2 + 2 + 1 = 5.
// expect: ifcount=2 rolled=5
void twoChildren(List<int> xs) {
  if (xs.isEmpty) return;
  // expect: ifcount=3
  xs.forEach((x) {
    if (x > 0) return;
    if (x < 0) return;
  });
  // expect: ifcount=2
  xs.forEach((x) {
    if (x > 0) return;
  });
}

// A local function is a measured child like a closure.
// expect: ifcount=1 rolled=2
void withLocal() {
  // expect: ifcount=2
  int helper(int v) {
    if (v > 0) return v;
    return 0;
  }

  helper(1);
}
