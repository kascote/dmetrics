// `?.`, `?..`, `?[]`, `!`: no authored alternative path, 0.
// expect: cyclomatic=1
int nullAware(List<int>? xs, StringBuffer? sb) {
  final n = xs?.length;
  sb
    ?..write('a')
    ..write('b');
  final first = xs?[0];
  return n! + first!;
}
