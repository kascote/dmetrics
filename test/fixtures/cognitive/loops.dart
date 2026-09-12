// Every loop form: +1 plus nesting. The header (init, condition, update,
// iterable) is read at the loop's level; only the body is one deeper.

// expect: cognitive=1
int forLoop(int n) {
  var s = 0;
  for (var i = 0; i < n; i++) {
    s += i;
  }
  return s;
}

// expect: cognitive=1
int forIn(List<int> xs) {
  var s = 0;
  for (final x in xs) {
    s += x;
  }
  return s;
}

// expect: cognitive=1
Future<int> awaitFor(Stream<int> xs) async {
  var s = 0;
  await for (final x in xs) {
    s += x;
  }
  return s;
}

// expect: cognitive=1
int whileLoop(int n) {
  while (n > 0) {
    n--;
  }
  return n;
}

// expect: cognitive=1
int doWhile(int n) {
  do {
    n--;
  } while (n > 0);
  return n;
}

// expect: cognitive=1
void forever() {
  for (;;) {
    break;
  }
}

// Nested loops with an `if` at the bottom: 1 + 2 + 3.
// expect: cognitive=6
int nested(List<List<int>> rows) {
  var s = 0;
  for (final row in rows) {
    for (final x in row) {
      if (x > 0) s += x;
    }
  }
  return s;
}

// A ternary in the loop header is at the loop's level, not its body's.
// expect: cognitive=2
int header(int n, bool fast) {
  var s = 0;
  for (var i = 0; i < n; i += fast ? 2 : 1) {
    s += i;
  }
  return s;
}

// A `while` condition with a boolean run: +1 loop, +1 run.
// expect: cognitive=2
int guarded(int n, int m) {
  while (n > 0 && m > 0) {
    n--;
    m--;
  }
  return n;
}
