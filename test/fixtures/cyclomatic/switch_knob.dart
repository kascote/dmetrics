// run: cyclomatic.count_case_arms=false
// With count_case_arms=false a switch is one decision (kind `switch`) and
// arms count 0. Guards and logical-or patterns still count.

// expect: cyclomatic=2
void statement(int a) {
  switch (a) {
    case 1:
      print(1);
    case 2:
    case 3:
      print(2);
    default:
      print('d');
  }
}

// expect: cyclomatic=2
String expression(int a) => switch (a) {
  1 => 'one',
  2 => 'two',
  _ => 'many',
};

// expect: cyclomatic=4
String guarded(Object o) => switch (o) {
  int x when x > 0 => 'pos', // +1 when
  1 || 2 => 'small', // +1 pattern-or
  _ => 'other',
};
