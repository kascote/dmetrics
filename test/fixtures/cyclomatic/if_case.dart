// if-case counts once (kind if-case), not if + pattern.
// expect: cyclomatic=2
void plain(Object o) {
  if (o case int x) print(x);
}

// Its when guard counts separately.
// expect: cyclomatic=3
void guarded(Object o) {
  if (o case int x when x > 0) print(x);
}

// else on an if-case: 0. else-if-case: +1, plus +1 for its guard.
// expect: cyclomatic=4
void chain(Object o) {
  if (o case int x) {
    print(x);
  } else if (o case String s when s.isNotEmpty) {
    print(s);
  } else {
    print('other');
  }
}
