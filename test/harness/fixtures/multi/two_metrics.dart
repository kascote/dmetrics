// Two metrics in one run: every scope needs an expectation for each.

// expect: ifcount=2 one=1
int f(int a) {
  if (a > 0) return 1;
  return 0;
}

// Stacked leading annotations merge onto the same target line.
// expect: ifcount=1
// expect: one=1
int g() => 0;

// expect: one=1 ifcount=1
int h() => 1;
