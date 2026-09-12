// Three-level roll-up: method 1, closure 2, inner closure 3 report 6 / 5 / 3
// under include_in_parent: value = measured + Σ child.value. Each child's
// score already carries the nesting of where it is written.
// expect: cognitive=1 rolled=6
void outer(List<int> xs) {
  if (xs.isEmpty) return; // +1
  // expect: cognitive=2 rolled=5
  xs.forEach((x) {
    if (x > 0) return; // +2
    // expect: cognitive=3
    [x].forEach((y) {
      if (y > 1) print(y); // +3
    });
  });
}
