// Base score 0. assert, return, throw, yield, await, labels without a jump,
// cascades, recursion: 0.

// expect: cognitive=0
void empty() {}

// expect: cognitive=0
Future<int> zero(StringBuffer sb) async {
  assert(sb.isNotEmpty);
  sb
    ..write('a')
    ..write('b');
  await Future<void>.delayed(Duration.zero);
  return recurse(sb);
}

// Recursion is 0 in v1: naming it needs resolution.
// expect: cognitive=0
int recurse(StringBuffer sb) => recurse(sb);

// expect: cognitive=0
Never boom() => throw StateError('x');

// expect: cognitive=0
Iterable<int> gen(int n) sync* {
  yield 1;
  yield* gen(n);
}

// A pattern assignment or declaration is 0: nothing can fail.
// expect: cognitive=0
int destructure((int, int) p) {
  final (a, b) = p;
  return a + b;
}
