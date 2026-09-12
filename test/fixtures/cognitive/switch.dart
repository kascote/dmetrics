// A `switch` counts once plus nesting, however many arms it has. Arms,
// patterns, `when` guards and `||` patterns are 0: they are the table.
// Cyclomatic counts every arm; this is the metric that scores a dispatch
// table as one decision.

// expect: cognitive=1
String words(int n) {
  switch (n) {
    case 1:
      return 'one';
    case 2:
      return 'a couple';
    case 3:
      return 'a few';
    default:
      return 'lots';
  }
}

// expect: cognitive=1
String expression(int n) => switch (n) {
  1 => 'one',
  2 => 'a couple',
  3 => 'a few',
  _ => 'lots',
};

// Patterns and guards are 0; the `&&` run inside a guard is a run: +1.
// expect: cognitive=2
String patterns(Object o) => switch (o) {
  int x when x > 0 && x < 10 => 'small',
  1 || 2 || 3 => 'few',
  (int a, int b) => '$a$b',
  String() => 'text',
  _ => 'other',
};

// Grouped labels share a body and still count as part of the one switch.
// expect: cognitive=1
bool grouped(int n) {
  switch (n) {
    case 1:
    case 2:
    case 3:
      return true;
    default:
      return false;
  }
}

// An arm's body is one level deep: the `if` inside is +2.
// expect: cognitive=3
String inArm(int n, bool loud) {
  switch (n) {
    case 1:
      if (loud) return 'ONE';
      return 'one';
    default:
      return 'lots';
  }
}

// A switch expression in an arm of a switch statement: +1, then +2.
// expect: cognitive=3
String nestedExpression(int n, int m) {
  switch (n) {
    case 1:
      return switch (m) {
        1 => 'a',
        _ => 'b',
      };
    default:
      return 'lots';
  }
}

// A switch inside an `if` body: +1 if, +2 switch.
// expect: cognitive=3
String inIf(int n, bool go) {
  if (go) {
    switch (n) {
      case 1:
        return 'one';
      default:
        return 'lots';
    }
  }
  return '';
}
