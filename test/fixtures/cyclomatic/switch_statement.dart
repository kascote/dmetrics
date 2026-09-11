// Constant arms are refutable: +1 each. default: 0.
// expect: cyclomatic=4
void constants(int a) {
  switch (a) {
    case 1:
      print(1);
    case 2:
      print(2);
    case 3:
      print(3);
    default:
      print('d');
  }
}

// Typed wildcards and typed bindings are tests; object, record, list, map
// and relational patterns too. A bare `_` is not.
// expect: cyclomatic=8
void patterns(Object o) {
  switch (o) {
    case int _: // +1 typed wildcard
      print('int');
    case String s: // +1 typed binding
      print(s);
    case Point(x: 0): // +1 object
      print('origin');
    case (int a, int b): // +1 record
      print(a + b);
    case [1, 2]: // +1 list
      print('list');
    case {'k': 1}: // +1 map
      print('map');
    case > 100: // +1 relational
      print('big');
    case _: // 0 bare wildcard
      print('any');
  }
}

// Untyped binding arms are irrefutable: 0. Their guards still count.
// Parenthesized irrefutable patterns stay irrefutable.
// expect: cyclomatic=2
void bindings(Object o) {
  switch (o) {
    case var x when x is int: // 0 arm, +1 when
      print(x);
    case (final y): // 0
      print(y);
  }
}

// Grouped labels sharing a body: +1 per label.
// expect: cyclomatic=4
void grouped(int a) {
  switch (a) {
    case 1:
    case 2:
    case 3:
      print('small');
    default:
      print('big');
  }
}

// Case labels and exhaustive switches without a wildcard: no adjustment.
// expect: cyclomatic=3
void labeled(bool b) {
  switch (b) {
    yes:
    case true:
      print('yes');
    case false:
      continue yes;
  }
}
