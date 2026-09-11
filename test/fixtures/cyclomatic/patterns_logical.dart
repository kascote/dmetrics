// Logical-or: +1 per extra alternative; the arm itself still counts once.
// expect: cyclomatic=4
String orTop(int a) => switch (a) {
  1 || 2 || 3 => 'small', // +1 arm, +2 alternatives
  _ => 'other',
};

// At any nesting depth.
// expect: cyclomatic=3
String orNested(Object o) => switch (o) {
  Point(x: 1 || 2) => 'near', // +1 arm, +1 alternative
  _ => 'far',
};

// Logical-and: 0. Both must match; part of the arm's single test.
// expect: cyclomatic=2
String and(Object o) => switch (o) {
  int _ && > 0 => 'pos', // +1 arm only
  _ => 'other',
};

// In an if-case, pattern-or counts too.
// expect: cyclomatic=3
void ifCaseOr(int a) {
  if (a case 1 || 2) print('small');
}
