// `c ? a : b`: +1 plus nesting. Both branches are one level deeper; the
// condition is not. There is no `else if` shorthand for ternaries: a chain
// in the else branch nests.

// expect: cognitive=1
int sign(int a) => a > 0 ? 1 : 0;

// expect: cognitive=3
int chain(int a) =>
    a > 0
        ? 1
        : a < 0
        ? -1
        : 0;

// expect: cognitive=3
int inThen(bool a, bool b) => a ? (b ? 1 : 2) : 3;

// The inner ternary is the condition of the outer: read at the same level.
// expect: cognitive=2
int inCondition(bool a, bool b, bool c) => (a ? b : c) ? 1 : 2;

// Inside an `if` body: +1 if, +2 ternary.
// expect: cognitive=3
int inIf(bool go, int a) {
  if (go) return a > 0 ? 1 : 0;
  return -1;
}

// A boolean run in a branch is a run, not a structure: +1 flat.
// expect: cognitive=2
bool runInBranch(bool go, bool a, bool b) => go ? a && b : false;
