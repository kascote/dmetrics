// expect: partial
// Deliberately invalid: `broken` is missing a semicolon. The recovered AST
// is still measured and every scope is marked partial.

// expect: cyclomatic=2
int ok(int a) {
  if (a > 0) return 1;
  return 0;
}

// expect: cyclomatic=2
int broken(int a) {
  if (a > 0) return 1;
  return 0
}
