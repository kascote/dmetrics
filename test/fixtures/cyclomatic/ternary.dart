// expect: cyclomatic=2
int sign(int a) => a >= 0 ? 1 : -1;

// Nested ternaries count each.
// expect: cyclomatic=3
int sign3(int a) => a > 0
    ? 1
    : a < 0
    ? -1
    : 0;
