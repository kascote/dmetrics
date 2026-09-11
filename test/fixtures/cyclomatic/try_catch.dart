// One per clause, binding or not: `on T catch (e)`, `on T`, `catch (e, st)`.
// try, finally, rethrow: 0.
// expect: cyclomatic=4
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

// expect: cyclomatic=1
void onlyFinally() {
  try {
    risky();
  } finally {
    print('done');
  }
}
