// Three-level roll-up (§6.3): method 2, closure 2, inner closure 2 report
// 4 / 3 / 2 under include_in_parent: value = measured + Σ(child.value − 1).
// expect: cyclomatic=2 rolled=4
void outer(List<int> xs) {
  if (xs.isEmpty) return;
  // expect: cyclomatic=2 rolled=3
  xs.forEach((x) {
    if (x > 0) return;
    // expect: cyclomatic=2
    [x].forEach((y) {
      if (y > 1) print(y);
    });
  });
}
