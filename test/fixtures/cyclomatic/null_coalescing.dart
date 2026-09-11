// `??` and `??=` count by default (count_null_coalescing=true).
// expect: cyclomatic=3
int coalesce(int? a) {
  var x = a ?? 0;
  x ??= 5;
  return x;
}
