// `if (x case P)` is an `if`: one test. Its pattern and `when` guard are 0;
// a boolean run in the guard is a run.

// expect: cognitive=1
String ifCase(Object o) {
  if (o case int x) return '$x';
  return '';
}

// expect: cognitive=2
String guarded(Object o) {
  if (o case int x when x > 0 && x < 10) return '$x';
  return '';
}

// expect: cognitive=3
String chain(Object o) {
  if (o case int x) {
    return '$x';
  } else if (o case String s when s.isNotEmpty) {
    return s;
  } else {
    return '';
  }
}

// expect: cognitive=1
String orPattern(Object o) {
  if (o case 1 || 2 || 3) return 'few';
  return '';
}
