// `if`: +1 plus one per enclosing nesting level. `else if` and `else`: +1
// each with no nesting increment, so a chain reads flat. Every branch body
// is one level deeper than the chain.

// expect: cognitive=1
int single(int a) {
  if (a > 0) return 1;
  return 0;
}

// expect: cognitive=3
int chain(int a) {
  if (a > 0) {
    return 1; // +1 if
  } else if (a < 0) {
    return -1; // +1 else-if
  } else {
    return 0; // +1 else
  }
}

// expect: cognitive=3
int nested(int a, int b) {
  if (a > 0) {
    // +1
    if (b > 0) return 1; // +2
  }
  return 0;
}

// expect: cognitive=9
int chainBodies(int a, int b) {
  if (a > 0) {
    // +1
    if (b > 0) return 1; // +2
  } else if (a < 0) {
    // +1
    if (b < 0) return -1; // +2
  } else {
    // +1
    if (b == 0) return 0; // +2
  }
  return 9;
}

// A condition is read at the level of its statement, not of its body.
// expect: cognitive=2
int condition(int a, int b) {
  if (a > (b > 0 ? 1 : 2)) return 1; // +1 if, +1 ternary
  return 0;
}

// An `else` on a nested `if` is +1 like any other; the dangling `else`
// binds to the inner `if`.
// expect: cognitive=4
int dangling(int a, int b) {
  if (a > 0) {
    // +1
    if (b > 0) return 1; // +2
    else return 2; // +1
  }
  return 0;
}

// Three levels: 1 + 2 + 3.
// expect: cognitive=6
int deep(int a, int b, int c) {
  if (a > 0) {
    if (b > 0) {
      if (c > 0) return 1;
    }
  }
  return 0;
}

// A structure in the `else` position is the chain link and a structure one
// level deep: +1 if, +1 else, +2 loop.
// expect: cognitive=4
int elseLoop(bool a, List<int> xs) {
  var s = 0;
  if (a) {
    s = 1;
  } else for (final x in xs) {
    s += x;
  }
  return s;
}

// expect: cognitive=4
int elseSwitch(bool a, int n) {
  if (a) {
    return 1;
  } else switch (n) {
    case 1:
      return 2;
    default:
      return 3;
  }
}
