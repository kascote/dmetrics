// `&&` and `||`: +1 each.
// expect: cyclomatic=4
bool check(int a, int b) => a > 0 && b > 0 || a == b && b != 0;

// Inside an if condition they add to the if.
// expect: cyclomatic=3
void inIf(int a, int b) {
  if (a > 0 || b > 0) print('x');
}
