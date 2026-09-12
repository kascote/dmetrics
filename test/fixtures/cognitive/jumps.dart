// A labeled `break` or `continue` is +1 flat: a jump the reader chases.
// Unlabeled `break`, `continue`, `return`, `throw`, `yield`: 0.

// expect: cognitive=5
int unlabeled(List<int> xs) {
  for (final x in xs) {
    // +1
    if (x < 0) continue; // +2, continue 0
    if (x > 9) break; // +2, break 0
  }
  return 0;
}

// expect: cognitive=7
int labeledBreak(List<List<int>> rows) {
  outer:
  for (final row in rows) {
    // +1
    for (final x in row) {
      // +2
      if (x == 0) break outer; // +3, +1 break
    }
  }
  return 0;
}

// expect: cognitive=1
void labeledBlock() {
  done:
  {
    break done; // +1
  }
}

// expect: cognitive=7
int labeledContinue(List<List<int>> rows) {
  var s = 0;
  outer:
  for (final row in rows) {
    // +1
    for (final x in row) {
      // +2
      if (x == 0) continue outer; // +3, +1 continue
      s += x;
    }
  }
  return s;
}
