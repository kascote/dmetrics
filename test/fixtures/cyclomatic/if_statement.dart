// expect: cyclomatic=2
void single(int a) {
  if (a > 0) print(a);
}

// `else if` is an if: +1 each. Bare `else`: 0.
// expect: cyclomatic=4
void chain(int a) {
  if (a > 0) {
    print('pos');
  } else if (a < 0) {
    print('neg');
  } else if (a == 0) {
    print('zero');
  } else {
    print('nan');
  }
}

// Nested ifs count each.
// expect: cyclomatic=3
void nested(int a, int b) {
  if (a > 0) {
    if (b > 0) print(b);
  }
}
