// A run of the same boolean operator counts once; the operator changing
// starts a new run. Runs never pay for nesting. `!` is 0. Parentheses do not
// break a run of the same operator but do start one when the operator
// inside differs from the one outside.

// expect: cognitive=1
bool oneRun(bool a, bool b, bool c) => a && b && c;

// expect: cognitive=2
bool twoRuns(bool a, bool b, bool c) => a && b || c;

// The whitepaper example: `&&`, `||`, `&&`.
// expect: cognitive=3
bool threeRuns(bool a, bool b, bool c, bool d, bool e, bool f) =>
    a && b && c || d || e && f;

// expect: cognitive=1
bool parenthesizedSame(bool a, bool b, bool c) => a && (b && c);

// expect: cognitive=3
bool parenthesizedMixed(bool a, bool b, bool c, bool d) =>
    (a && b) || (c && d);

// expect: cognitive=2
bool negated(bool a, bool b, bool c) => !(a && b) || c;

// In an `if` condition the run is +1 flat next to the +1 `if`.
// expect: cognitive=2
void inIf(bool a, bool b) {
  if (a && b) print('x');
}

// Nested `if` with a run: +1, +2, +1. The run pays nothing for nesting.
// expect: cognitive=4
void nestedIf(bool a, bool b, bool c) {
  if (a) {
    if (b && c) print('x');
  }
}

// Precedence: `a || b && c` is `||` over `&&`: two runs.
// expect: cognitive=2
bool precedence(bool a, bool b, bool c) => a || b && c;

// Runs in separate expressions are separate runs.
// expect: cognitive=2
bool separate(bool a, bool b, bool c, bool d) {
  final x = a && b;
  final y = c && d;
  return x == y;
}
