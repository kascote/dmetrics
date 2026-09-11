// run: cyclomatic.count_null_coalescing=false

// expect: cyclomatic=1
int coalesce(int? a) {
  var x = a ?? 0;
  x ??= 5;
  return x;
}

// Other constructs are unaffected by the knob.
// expect: cyclomatic=2
int other(int? a) => a == null ? 0 : a;
