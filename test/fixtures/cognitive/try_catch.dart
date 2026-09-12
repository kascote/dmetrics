// `catch` (binding or not, `on T` or not): +1 plus nesting, and its body is
// one level deeper. `try`, `finally` and `rethrow`: 0, and the `try` body
// is not nested.

// expect: cognitive=3
void clauses() {
  try {
    risky();
  } on FormatException catch (e) {
    print(e);
  } on StateError {
    print('state');
  } catch (e, st) {
    print(st);
    rethrow;
  } finally {
    print('done');
  }
}

// expect: cognitive=0
void onlyFinally() {
  try {
    risky();
  } finally {
    print('done');
  }
}

// The `try` body is read at the statement's level: the `if` is +1.
// expect: cognitive=1
void inTry(bool go) {
  try {
    if (go) risky();
  } finally {
    print('done');
  }
}

// The `catch` body is one level deep: +1 catch, +2 if.
// expect: cognitive=3
void inCatch(bool loud) {
  try {
    risky();
  } catch (e) {
    if (loud) print(e);
  }
}

// A `catch` inside an `if` body: +1 if, +2 catch.
// expect: cognitive=3
void catchInIf(bool go) {
  if (go) {
    try {
      risky();
    } catch (e) {
      print(e);
    }
  }
}

// expect: cognitive=0
void risky() {}
