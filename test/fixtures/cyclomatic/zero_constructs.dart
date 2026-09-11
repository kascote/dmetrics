// assert, return, break, continue, throw, yield, await, labels, cascades,
// recursion: 0.
// expect: cyclomatic=1
Future<int> zero(StringBuffer sb) async {
  assert(sb.isNotEmpty);
  sb
    ..write('a')
    ..write('b');
  await Future<void>.delayed(Duration.zero);
  outer:
  {
    break outer;
  }
  return recurse(sb);
}

// expect: cyclomatic=1
int recurse(StringBuffer sb) => recurse(sb);

// expect: cyclomatic=1
Never boom() => throw StateError('x');

// expect: cyclomatic=1
Iterable<int> gen(int n) sync* {
  yield 1;
  yield* gen(n);
}
