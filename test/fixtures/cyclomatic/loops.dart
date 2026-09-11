// for, for-in, await for, while, do-while: +1 each (kind loop).
// expect: cyclomatic=6
Future<void> loops(List<int> xs, Stream<int> s) async {
  for (var i = 0; i < 3; i++) {
    print(i);
  }
  for (final x in xs) {
    print(x);
  }
  await for (final v in s) {
    print(v);
  }
  while (xs.isEmpty) {
    break;
  }
  do {
    print(1);
  } while (xs.isEmpty);
}

// `for (;;)` with no condition still counts: uniformity over CFG purity.
// expect: cyclomatic=2
void forever() {
  for (;;) {
    break;
  }
}
