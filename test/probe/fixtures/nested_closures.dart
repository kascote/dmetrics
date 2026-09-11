// The method sees depth 1 only: everything inside the closure belongs to the
// closure. A leaked node event would report 3 here.
// expect: nesting=1 rolled=2
void m(List<int> xs) {
  if (xs.isEmpty) {
    // expect: nesting=2
    xs.forEach((x) {
      if (x > 0) {
        if (x > 1) print(x);
      }
    });
  }
}

// A sibling after `m` starts from depth 0 again, which only holds when exit
// events fired for every `if` above.
// expect: nesting=2
void after(int a) {
  if (a > 0) {
    for (;;) {}
  }
}

// Sequential statements do not nest.
// expect: nesting=1
void seq(int a) {
  if (a > 0) {}
  if (a > 1) {}
  if (a > 2) {}
}

// Three levels: method 1, closure 1, inner closure 2. Roll-up is max.
// expect: nesting=1 rolled=2
void three(List<int> xs) {
  if (xs.isEmpty) {
    // expect: nesting=1 rolled=2
    xs.forEach((x) {
      if (x > 0) {
        // expect: nesting=2
        [x].forEach((y) {
          while (y > 0) {
            if (y > 1) y--;
          }
        });
      }
    });
  }
}
